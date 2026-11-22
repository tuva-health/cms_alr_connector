# AGENTS.md

This file provides guidance to Agents when working with code in this repository.

## Project Overview

This is a dbt package (`cms_aalr_connector`, repo [tuva-health/cms_alr_connector](https://github.com/tuva-health/cms_alr_connector)) that transforms raw CMS Medicare Shared Savings Program Assignment List Reports (quarterly QALR and annual AALR) into enrollment data for the [Medicare CCLF Connector](https://github.com/tuva-health/medicare_cclf_connector), which feeds [Tuva Core](https://github.com/tuva-health/tuva-core) 1.0 (dbt package name `the_tuva_project`). `packages.yml` pins medicare_cclf_connector `v1.0.2`, which pins Tuva Core `v1.0.0`; Tuva Core is not declared here, so bump it by moving the CCLF pin. Client projects such as [cms_mssp_connector](https://github.com/tuva-health/cms_mssp_connector) install it as a package. Supported warehouses are DuckDB and Snowflake, the ones CI builds.

## Before you start

- **Running dbt, tests or CI**: read [integration_tests/README.md](integration_tests/README.md).
  Every run uses `--project-dir integration_tests`; the toolchain is `uv` and `uv.lock`.
- **Opening a PR**: apply exactly one release label (`breaking-change`,
  `enhancement`, `bug`, `docs`, `ignore-for-release`); the generated
  release notes are grouped by it.
- **Releasing or bumping `version:`**: read the Releasing section of [README.md](README.md#-releasing).

## Common Commands

Development runs go through the `integration_tests` dbt project, which installs this package from `local: ../` and loads fixture seeds where `source()` expects the raw ALR and CCLF tables. `scripts/dbt-local` runs dbt against it with the uv-locked toolchain and a local DuckDB file. See [integration_tests/README.md](integration_tests/README.md) for the CI checks, the Snowflake setup and the var inventory.

```bash
# Install dependencies (resolved from ../packages.yml; integration_tests/package-lock.yml is not committed)
scripts/dbt-local deps

# Load the fixture seeds
scripts/dbt-local seed --full-refresh --select package:integration_tests

# Build and test the connector (what the dbt build / duckdb check runs)
scripts/dbt-local build --full-refresh \
  --select +package:cms_aalr_connector package:integration_tests \
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
medicare_cclf_connector → the_tuva_project (Tuva Core 1.0)
```

### Model Layers

- **`models/staging/`** (`stg_aalr{N}_*.sql`): Views over raw source tables. Each model corresponds to one CMS AALR report section (AALR1, AALR2, AALR4, AALR5, AALR6, AALR9). These only cast data types using custom macros — no business logic.

- **`models/intermediate/`**: Five tables that handle the complex transformations:
  - `aalr_history`: Joins all staging models, pivots 12 monthly `enrollflag` columns into individual rows (one per enrollment month), keeps the top TIN (by encounter count, ties to the lowest `MASTER_ID`) and, under it, the top NPI (by PCS count, ties to the lowest `NPI_USED`) from the same delivery as the Table 1-1 row (`DELIVERY_ID`) with `row_number()` (not `dbt_utils.deduplicate()`, whose DuckDB implementation drops rows with NULL columns), and enriches with turnover/voluntary/underserved flags.
  - `aalr_file_parameters`: The parameters every ALR file is placed by (TUVA-164): the `mssp_file_parameters` seed plus a derived row (calendar year `Y<yyyy>`, the seed's benchmark priority) for each delivered benchmark AALR the seed has no row for. Benchmark years are fixed for an agreement period, so an ACO past its first year gets benchmark AALRs older than the seed's PY-3..PY-1 rows. `aalr_history` (Table 1-1 and turnover), `aalr_governing_file` and `aalr_settlement_population` join it, never the seed directly. A file it has no row for is left out of `aalr_history` and `aalr_governing_file` and fails the package test `tests/alr_file_without_file_parameters.sql` (macro `alr_files_without_file_parameters()`).
  - `aalr_governing_file`: One row per (ACO, `enroll_month`): the file that governs the month (earliest covering performance year, then the `priority` field from `aalr_file_parameters`, then the later T-stamp; a benchmark, delivered with the following performance year, governs only months no earlier year's file covers). It supplies all ALR-sourced fields for the month; CCLF's `data_sharing_flag` comes from CCLF8 and is unaffected. See the README's "Which file decides each month".
  - `aalr_history_filtered`: Keeps only the `aalr_history` rows from each month's governing file, one per beneficiary-month.
  - `aalr_settlement_population`: The settlement population (TUVA-113): one row per beneficiary and settlement (STLMT) AALR delivery, with its Table 1-1 row, top TIN/NPI (the `aalr_top_tin_and_npi()` macro, shared with `aalr_history`), Table 1-6/1-9 fields and person-years, joined on `DELIVERY_ID`; `is_latest_delivery` marks the latest T-stamp (embargoed T0000000 vs unembargoed T1111111). A settlement AALR never governs a month: `aalr_history` and `aalr_governing_file` exclude it explicitly, and nothing else reads this model.

- **`models/final/enrollment.sql`**: Converts the filtered history into the CCLF connector's expected enrollment format — calculates month start/end dates, formats `member_month` as YYYYMM, filters to `enroll_flag > 0`, and publishes `enroll_flag` (1 ESRD, 2 Disabled, 3 Aged/Dual, 4 Aged/Non-Dual) from the governing file.
- **`models/final/provider_attribution.sql`**: Tuva Core 1.0's `input_layer__provider_attribution` contract (it selects `*` from this model; `normalized__provider_attribution` reads the contract columns by name, including `file_name` and `ingest_datetime`). A missing contract column fails the Tuva build, so check the contract in `dbt_packages/the_tuva_project/models/input_layer/` when the Tuva Core pin moves.

### Key Design Patterns

**File metadata extraction**: The `extract_file_metadata()` macro parses AALR filenames to determine file type, performance year, iteration, and period, plus `ALR_FILE_TYPE` (`quarterly`, `initial`, `benchmark`, `settlement`) and `DELIVERY_ID` (the file name without `_1-<table>.csv`). Performance year, period and `ALR_FILE_TYPE` join to `aalr_file_parameters` (the `mssp_file_parameters` seed plus derived benchmark rows) to determine file priority (lower priority number = more recent/preferred file). Join ALR tables to each other on `DELIVERY_ID`, never on (ACO, performance year, period, T-stamp): a settlement AALR (`AALR.Y2025.D259999` for PY2025) and the initial assignment can share all four (TUVA-152). Settlement AALRs have seed rows (blank `priority`) but never govern a month (TUVA-113): `aalr_history` filters them out explicitly (Table 1-1 and 1-5 CTEs) and `aalr_governing_file` excludes them in `delivered_files`. Keep both filters: a seed row alone would let a settlement govern, and a settlement row in `aalr_history` could push the governing file's row off `row_number = 1` in `aalr_history_filtered`.

**Multi-database compatibility**: All macros use dbt's adapter dispatch pattern (`{{ adapter.dispatch(...) }}`), with implementations for BigQuery, Databricks, Fabric, MotherDuck, Redshift, and Snowflake. Only DuckDB and Snowflake are supported: CI builds those two, and the other implementations are untested.

**Type-safe casting**: Use `{{ cast_numeric(column) }}` and `{{ try_to_cast_date(column, format) }}` macros instead of raw SQL `CAST()` to maintain cross-database compatibility. Counts and dollar amounts use `cast_numeric` (`numeric(38,2)`); the CMS-HCC risk scores and the person-years fractions (`bene_psnyrs_dual`, and Table 1-9's `bene_psnyrs` and `bene_psnyrs_lis_dual`) use `cast_score` (`numeric(38,14)`, `BIGNUMERIC` on BigQuery) so the decimals CMS ships survive to `enrollment`. A unit test on `stg_aalr1_assigned_beneficiaries` pins that precision.

### Key Variables

The defaults below are this repo's `dbt_project.yml`, which only applies inside the package. A consuming project (or `integration_tests/dbt_project.yml`, the canonical inventory) sets them as global vars.

| Variable | Default | Purpose |
|---|---|---|
| `input_database` | `tuva` | Source database for CMS data |
| `input_schema` | `raw_data` | Source schema for CMS data |
| `tuva_schema_prefix` | (none) | Prefix for output schemas (multi-tenant) |
| `claims_enabled` | `true` | Enable claims processing |
| `cms_alr_connector` | `true` | Read by medicare_cclf_connector: take enrollment from this package's `enrollment` model |

Neither this package nor medicare_cclf_connector v1.0.2 reads `demo_data_only`; sources are always enabled. Tuva Core 1.0 also needs `flags: require_ref_searches_node_package_before_root: true`, which dbt reads only from the root project: it is set in this repo's `dbt_project.yml`, in `integration_tests/dbt_project.yml`, and must be set in every consuming project.

### Seeds

`seeds/mssp_file_parameters.csv` maps CMS file metadata to performance periods (2016–2026). The `priority` column determines file precedence when multiple AALR files exist for the same period — lower priority = more recent/preferred. Settlement rows (calendar performance year) have no priority; `integration_tests/tests/mssp_file_parameters_periods.sql` checks that. Benchmark rows only cover the first year of an agreement period; `aalr_file_parameters` derives the rest, so rows for other benchmark years aren't needed.

### Precedence explainer page

`docs/alr-month-precedence.html` is a self-contained, interactive explainer of `aalr_governing_file` for stakeholders, linked from the README's "Which file decides each month". It ports the model's ranking to JavaScript and embeds every `mssp_file_parameters` row in its `mssp-file-parameters` JSON block. If you change `aalr_governing_file` or the seed, update the page in the same PR: for a seed change run `uv run --script scripts/check_precedence_doc.py --write`, and for a rule change edit the page's logic and walkthroughs to match. The page keys seed rows by (performance year, period, file type), as the model does: `Y2025` is PY2025's initial and settlement file. The `uv lock check` job fails when the embedded rows differ from the seed; it does not check the logic.

### Sources

All six source tables live at `{{ var('input_database') }}.{{ var('input_schema') }}` and are defined in `models/_sources.yml`.
