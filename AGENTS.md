# AGENTS.md

This file provides guidance to Agents when working with code in this repository.

## Project Overview

This is a dbt project (`cms_aalr_connector`) that transforms raw CMS Medicare Advanced ACO Assignment List Reports (AALR) into enrollment data for the [Medicare CCLF Connector](https://github.com/z2healthinsights/medicare_cclf_connector), which feeds into the [Tuva Project](https://github.com/tuva-health/the_tuva_project) healthcare analytics framework.

## Common Commands

```bash
# Install dependencies
dbt deps

# Run all models
dbt build

# Run a specific model
dbt run --select <model_name>

# Run a model and all its upstream dependencies
dbt run --select +<model_name>

# Run tests
dbt test

# Run seed data
dbt seed

# Override variables at runtime
dbt build --vars '{"input_database": "mydb", "input_schema": "myschema", "tuva_schema_prefix": "prefix"}'
```

## Architecture

### Data Flow

```
Raw CMS AALR source tables (6)
        ↓
Staging models (views) — type casting & column selection only
        ↓
Intermediate models (tables) — enrichment, pivoting, deduplication, file precedence
        ↓
Final enrollment model (table) — CCLF connector input format
        ↓
medicare_cclf_connector → the_tuva_project
```

### Model Layers

- **`models/staging/`** (`stg_aalr{N}_*.sql`): Views over raw source tables. Each model corresponds to one CMS AALR report section (AALR1, AALR2, AALR4, AALR5, AALR6, AALR9). These only cast data types using custom macros — no business logic.

- **`models/intermediate/`**: Two tables that handle the complex transformations:
  - `aalr_history`: Joins all staging models, pivots 12 monthly `enrollflag` columns into individual rows (one per enrollment month), deduplicates by TIN (by encounter count) and NPI (by PCS count) using `dbt_utils.deduplicate()`, and enriches with turnover/voluntary/underserved flags.
  - `aalr_history_filtered`: Filters to the latest AALR file per `enrollment_month`/`performance_year` using the `priority` field from the `mssp_file_parameters` seed.

- **`models/final/enrollment.sql`**: Converts the filtered history into the CCLF connector's expected enrollment format — calculates month start/end dates, formats `member_month` as YYYYMM, and filters to `enroll_flag > 0`.

### Key Design Patterns

**File metadata extraction**: The `extract_file_metadata()` macro parses AALR filenames to determine file type, performance year, iteration, and period. This metadata joins to the `mssp_file_parameters` seed to determine file priority (lower priority number = more recent/preferred file).

**Multi-database compatibility**: All macros use dbt's adapter dispatch pattern (`{{ adapter.dispatch(...) }}`), with implementations for BigQuery, Databricks, Fabric, MotherDuck, Redshift, and Snowflake.

**Type-safe casting**: Use `{{ cast_numeric(column) }}` and `{{ try_to_cast_date(column, format) }}` macros instead of raw SQL `CAST()` to maintain cross-database compatibility. Counts and dollar amounts use `cast_numeric` (`numeric(38,2)`); the CMS-HCC risk scores and `bene_psnyrs_dual` use `cast_score` (`numeric(38,10)`, `BIGNUMERIC` on BigQuery) so the decimals CMS ships survive to `enrollment`. A unit test on `stg_aalr1_assigned_beneficiaries` pins that precision.

### Key Variables

| Variable | Default | Purpose |
|---|---|---|
| `input_database` | `tuva` | Source database for CMS data |
| `input_schema` | `raw_data` | Source schema for CMS data |
| `tuva_schema_prefix` | (none) | Prefix for output schemas (multi-tenant) |
| `demo_data_only` | `false` | Toggle demo vs. production data |
| `claims_enabled` | `true` | Enable claims processing |

### Seeds

`seeds/mssp_file_parameters.csv` maps CMS file metadata to performance periods (2016–2026). The `priority` column determines file precedence when multiple AALR files exist for the same period — lower priority = more recent/preferred.

### Sources

All six source tables live at `{{ var('input_database') }}.{{ var('input_schema') }}` and are defined in `models/_sources.yml`.
