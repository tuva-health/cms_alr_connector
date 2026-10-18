# AGENTS.md

This file provides guidance to Agents when working with code in this repository.

## Project Overview

This is a dbt package (`cms_aalr_connector`, repo [tuva-health/cms_alr_connector](https://github.com/tuva-health/cms_alr_connector)) that transforms raw CMS Medicare Shared Savings Program Assignment List Reports (quarterly QALR and annual AALR) into enrollment data for the [Medicare CCLF Connector](https://github.com/tuva-health/medicare_cclf_connector), which feeds into the [Tuva Project](https://github.com/tuva-health/the_tuva_project) healthcare analytics framework. Client projects such as [cms_mssp_connector](https://github.com/tuva-health/cms_mssp_connector) install it as a package. Supported warehouses are DuckDB and Snowflake, the ones CI builds.

## Common Commands

Development runs go through the `integration_tests` dbt project, which installs this package from `local: ../` and loads fixture seeds where `source()` expects the raw ALR and CCLF tables. `scripts/dbt-local` runs dbt against it with the uv-locked toolchain and a local DuckDB file. See [integration_tests/README.md](integration_tests/README.md) for the CI checks, the Snowflake setup and the var inventory.

```bash
# Install dependencies (from integration_tests/package-lock.yml)
scripts/dbt-local deps

# Load the fixture seeds
scripts/dbt-local seed --full-refresh --select package:integration_tests

# Build and test the connector (what the dbt build / duckdb check runs)
scripts/dbt-local build --full-refresh \
  --select package:cms_aalr_connector package:integration_tests \
  --exclude package:integration_tests,resource_type:seed --indirect-selection cautious

# Run a model and all its upstream dependencies
scripts/dbt-local build --select +<model_name>

# Override variables at runtime
scripts/dbt-local build --vars '{"input_database": "mydb", "input_schema": "myschema", "tuva_schema_prefix": "prefix"}'

# Check uv.lock matches pyproject.toml (the uv lock check)
uv lock --check
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

**Multi-database compatibility**: All macros use dbt's adapter dispatch pattern (`{{ adapter.dispatch(...) }}`), with implementations for BigQuery, Databricks, Fabric, MotherDuck, Redshift, and Snowflake. Only DuckDB and Snowflake are supported: CI builds those two, and the other implementations are untested.

**Type-safe casting**: Use `{{ cast_numeric(column) }}` and `{{ try_to_cast_date(column, format) }}` macros instead of raw SQL `CAST()` to maintain cross-database compatibility. Counts and dollar amounts use `cast_numeric` (`numeric(38,2)`); the CMS-HCC risk scores and `bene_psnyrs_dual` use `cast_score` (`numeric(38,10)`, `BIGNUMERIC` on BigQuery) so the decimals CMS ships survive to `enrollment`. A unit test on `stg_aalr1_assigned_beneficiaries` pins that precision.

### Key Variables

The defaults below are this repo's `dbt_project.yml`, which only applies inside the package. A consuming project (or `integration_tests/dbt_project.yml`, the canonical inventory) sets them as global vars.

| Variable | Default | Purpose |
|---|---|---|
| `input_database` | `tuva` | Source database for CMS data |
| `input_schema` | `raw_data` | Source schema for CMS data |
| `tuva_schema_prefix` | (none) | Prefix for output schemas (multi-tenant) |
| `claims_enabled` | `true` | Enable claims processing |
| `cms_alr_connector` | `true` | Read by medicare_cclf_connector: take enrollment from this package's `enrollment` model |

This package no longer reads `demo_data_only`; its sources are always enabled. The pinned medicare_cclf_connector revision still reads it and defaults it to `true`, so consuming projects keep `demo_data_only: false` until that pin moves.

### Seeds

`seeds/mssp_file_parameters.csv` maps CMS file metadata to performance periods (2016–2026). The `priority` column determines file precedence when multiple AALR files exist for the same period — lower priority = more recent/preferred.

### Sources

All six source tables live at `{{ var('input_database') }}.{{ var('input_schema') }}` and are defined in `models/_sources.yml`.
