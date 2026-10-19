# Integration tests

`integration_tests` is the dbt project used for local development and CI of
`cms_aalr_connector`. It installs the connector as a local package
(`packages.yml` → `local: ../`), which brings in `medicare_cclf_connector`
v1.0.0 and, through it, Tuva Core v1.0.0 (dbt package name
`the_tuva_project`). It loads fixture seeds where both connectors' `source()`
expects raw tables and builds them against those seeds. All CI and local runs
use `--project-dir integration_tests`.

## Layout

- `dbt_project.yml`: the canonical, commented inventory of the vars the
  connector and the packages it installs read. They are set here as global
  vars, so they reach `medicare_cclf_connector` and `the_tuva_project` too,
  exactly as in a client project. `cms_alr_connector: true` makes
  `medicare_cclf_connector` take enrollment from this connector's
  `enrollment` model.
- `packages.yml`: the connector only. `dbt deps` resolves its packages from
  `../packages.yml` on every run; the `package-lock.yml` it writes here is
  gitignored. Every pin is a release tag, so the only thing that can float is
  `dbt_utils` within the range its dependents allow (the root
  `package-lock.yml` records the set this release was built with).
- `dbt_project.yml` also sets `require_ref_searches_node_package_before_root`,
  which Tuva Core 1.0 requires and dbt reads only from the root project.
- `seeds/`: fixture seeds, one per raw table: the six ALR tables
  (`aalr1/2/4/5/6/9_*`, source `cms_ssp_reports`) and the CCLF tables of the
  `medicare_cclf_connector` v1.0.0 sources (source `medicare_cclf`). They load
  into `var('input_database')`.`var('input_schema')`, so the connectors read
  them exactly as they read a client's raw tables. Every column loads as a
  string. The seeds hold synthetic fixtures (see Fixtures below). There is no
  seed for the CCLF `enrollment` source, which `cms_alr_connector: true`
  replaces with this connector's `enrollment` model.
- `tests/`: integration-only singular tests.
- `macros/`: CI helpers: schema naming, unit-test schema setup
  (`ensure_unit_test_schemas`, an on-run-start hook), and
  `drop_ci_schemas` for per-run cleanup.
- `profiles/`: one profile per supported warehouse. `profiles/local_duckdb`
  is the default for local runs and the DuckDB CI job; `profiles/snowflake` is
  the Snowflake CI job's.

## Fixtures

The seeds are small, fully synthetic ALR and CCLF tables. A generator kept
outside this repository builds them deterministically. Every identifier is
invented and visibly fake (MBIs `9TT0FK…`, ACO `A0000`, TINs `00100000#`, NPIs
`199990…`, SSA state-county `00103`, names `SYN…`/`CCLFTEST`/`ALRTEST`), and all
dates fall in an invented 2023-10 to 2026-03 window. No real beneficiary or
provider data is committed, and fixture files must not be hand-edited: change
and rerun the generator instead.

The ALR seeds hold seven deliveries for one ACO. `file_name` is the inner CSV
name CMS ships (`P.A0000.ACO.QALR.2025Q1.D259999.T0100000_1-1.csv`) and
`directory_name` the nested zip that holds it:

| delivery | inner ALR | window |
| --- | --- | --- |
| initial assignment (HASSGN) | `AALR.D259999.T0000000` | 2023-10..2024-09 |
| benchmark (BNMRK) | `AALR.Y2024.D259999.T1111111` | 2024 |
| quarterly (QEXPU) | `QALR.2025Q1`..`2025Q3`, `T0100000`..`T0300000` | 2024-04.. to ..2025-09 |
| redelivery | `QALR.2025Q3.D259999.T0310000` | 2024-10..2025-09 |
| next performance year | `QALR.2026Q1.D269999.T0100000` | 2025-04..2026-03 |

The CCLF seeds are byte-identical to medicare_cclf_connector v1.0.0's own
fixtures (same generator) for every table it reads except `enrollment`, and
share their beneficiaries (9TT0FK0XX01-28) with the ALR seeds.

Each scenario has a singular test in `tests/` (`fixture_<scenario>.sql`) that
returns the rows breaking the outcome the CMS ALR specifications call for. The
tests do not assert the connector's current behaviour. For each beneficiary
and month, the governing ALR is chosen within the earliest performance year
whose files cover that month: the file ranked last in initial, Q1, Q2, Q3, Q4,
benchmark (the benchmark governs every month it covers), and a later T-stamp
of the same period wins. A beneficiary the governing file does not list is
not enrolled for that month. The scenarios cover:

- a later quarterly ALR superseding earlier ones (A01) and the month
  precedence between initial, benchmark and quarterly files (A02, A03);
- turnover: a drop-out listed in Table 1-5 (A02) and a re-entry (A02b);
- a period redelivered under a later T-stamp: counted once with corrected
  values (A04), a beneficiary removed (A04b), Table 1-2/1-4 rows removed (A04c);
- EnrollFlag codes 0-4 and gaps (A05), deaths (A06), 14-decimal risk scores
  (A07);
- provider attribution with several TINs and NPIs (A08) and none (A08b);
- Tables 1-6 and 1-9 (A09, A09b);
- ALR months matching the CCLF fixtures' enrollment (A10), an initial-assignment
  file (A11), overlapping performance years (A12), and an MBI change across
  performance years (A13).

Tests for known connector bugs carry the Linear issue key as a tag and fail
until the bug is fixed, e.g. `--select tag:tuva-110`. Every fixture test
carries the `fixture` tag and depends on both final models, so a failing test
never skips `enrollment` or `provider_attribution`.

`tests/mssp_file_parameters_periods.sql` checks the connector's
`mssp_file_parameters` seed itself: every row covers 12 whole months and each
benchmark row covers calendar `report_year`. No fixture delivers every period
in the seed, so this is what guards the periods the fixtures don't reach.

## Local runs

From the repo root, `scripts/dbt-local` runs dbt with the uv-locked toolchain
(every adapter extra in `pyproject.toml`) against this project and the local
DuckDB profile (`/tmp/cms_alr_connector_ci.duckdb`):

```sh
scripts/dbt-local deps
scripts/dbt-local seed --full-refresh --select package:integration_tests
scripts/dbt-local build --full-refresh \
  --select +package:cms_aalr_connector package:integration_tests \
  --exclude package:integration_tests,resource_type:seed --indirect-selection cautious
```

To build everything a client project builds (both connectors, the_tuva_project
and its dependencies), select `fqn:*` with `--indirect-selection eager`
instead. Set `DBT_PROFILES_DIR` (and `DBT_PROFILE`) to use another warehouse.
Without the wrapper: `uv run --extra duckdb dbt <cmd> --project-dir
integration_tests --profiles-dir integration_tests/profiles/local_duckdb`.

## CI

Every pull request runs `.github/workflows/ci.yml`, whatever its base branch,
so stacked PRs get the same checks. Pull requests to `main` also run
`.github/workflows/release-label.yml`:

| Check | What it runs |
| --- | --- |
| `uv lock check` | `uv lock --check`: `uv.lock` is the single toolchain pin. Then `scripts/check_precedence_doc.py`: the `mssp_file_parameters` rows embedded in `docs/alr-month-precedence.html` match `seeds/mssp_file_parameters.csv`. |
| `dbt build / duckdb` | deps, parse, fixture seeds, connector unit tests, connector build (with the medicare_cclf_connector crosswalk models `provider_attribution` reads). No secrets; runs on fork PRs too. |
| `dbt build / snowflake` | Same steps, then builds the connector and every installed package (medicare_cclf_connector, the_tuva_project and its dependencies) downstream. Same-repo PRs only. |
| `CI / Snowflake` | Commit status on the PR head carrying the Snowflake build's result. Same-repo PRs get it from `ci.yml`; fork PRs only from [External PR CI](#fork-pull-requests). |
| `release label` | The PR has exactly one release label (see the Releasing section of the root README). |

The required checks are `uv lock check`, `dbt build / duckdb`, `CI / Snowflake`
and `release label`. `CI / Snowflake` stands in for `dbt build / snowflake`:
that job is skipped on fork PRs, and GitHub counts a skipped check as passing,
whereas a missing status blocks the merge until a maintainer has run the
Snowflake build.

The seeds load before the unit tests: the unit test on
`stg_aalr1_assigned_beneficiaries` mocks a source, and dbt reads the source
table's columns to build the mock.

Each job installs only its warehouse's adapter: `uv sync --locked --extra
<warehouse>`, one `pyproject.toml` extra per supported warehouse.

Each Snowflake run sets `tuva_schema_prefix` to
`ci_pr_<pr>_<head sha8>_r<run id>_a<attempt>`, loads fixtures into
`<prefix>_raw`, and writes every connector and Tuva schema as `<prefix>_*` or
`_<prefix>_*`; the profile's default schema is `<prefix>_default`. A final
`always()` step runs `drop_ci_schemas` to drop them, so concurrent PRs never
share schemas. A new push cancels the PR's in-flight run.

`ci.yml` is also a reusable workflow (`workflow_call`) with inputs `warehouse`
(`duckdb`, `snowflake`, or `all`), `scope` (`full` or `connector`),
`checkout_ref`, and `schema_prefix`. With `publish_status`, plus the PR number,
its base branch and its exact base, head and test-merge commits, it posts a
commit status (`CI / Snowflake`, or `CI / All Warehouses` for `all`) on the PR
head: pending when it starts, then the result. The status reports an error instead if the PR
or its base branch moves while CI runs, and a run never overwrites a newer
run's status. **Re-run** cannot clear that error: it replays the old event,
with the old base. Push a commit, or close and reopen the PR. Retargeting a PR
(by hand, or when a stacked PR's parent merges) starts no run on its own, so
retarget between runs, not during one.

### Fork pull requests

Fork PRs get the DuckDB check automatically; the Snowflake job is skipped
because it would expose repository secrets to fork code. After reviewing the
PR's code, a maintainer runs **Actions → External PR CI → Run workflow** from
`main` with the PR number. It pins the PR's current test-merge commit, runs
the Snowflake build through `ci.yml`, and posts `CI / Snowflake` on the PR
head. Rerun it after every new push to the fork PR.

### All warehouses

`CI -- All Warehouses` (`ci-all-warehouses.yml`) is the release gate. A
maintainer runs it from `main` with a same-repo PR's number before a release PR
merges; it builds the PR's test merge with `warehouse: all` and posts
`CI / All Warehouses` on the PR head. `all` is DuckDB and Snowflake, the
warehouses the root README lists as supported. It is not a required check,
since every PR would then need it.

To support another warehouse, add all of these in one PR: a `pyproject.toml`
extra for its adapter (then `uv lock`), a profile under `profiles/`, its secrets
and a case in `ci.yml` (the `all` warehouse list and the warehouse job's
settings check and `input_database`), and the README list, once a run passes.

## Snowflake authentication

Use a dedicated Snowflake service user with key-pair authentication. Repository
secrets live under **Settings → Secrets and variables → Actions**. Configure:

| Repository secret | Value |
| --- | --- |
| `DBT_SNOWFLAKE_CI_ACCOUNT` | Snowflake account identifier, without `https://` or `.snowflakecomputing.com` |
| `DBT_SNOWFLAKE_CI_USER` | Service user's login name |
| `DBT_SNOWFLAKE_CI_ROLE` | Role assigned to the service user |
| `DBT_SNOWFLAKE_CI_WAREHOUSE` | CI warehouse |
| `DBT_SNOWFLAKE_CI_DATABASE` | Dedicated, disposable CI database |
| `DBT_SNOWFLAKE_CI_SCHEMA` | Unused by `ci.yml`, which sets the profile's default schema to `<prefix>_default` per run |
| `DBT_SNOWFLAKE_CI_PRIVATE_KEY` | Entire PKCS#8 PEM private key, including header/footer and line breaks |
| `DBT_SNOWFLAKE_CI_PRIVATE_KEY_PASSPHRASE` | Passphrase for an encrypted key; omit for an unencrypted key |

The role needs warehouse usage, database usage, and permission to create
schemas and build objects in the CI database (each run creates and drops its
own schemas). Use the existing CI role where possible.

### Generate and register a key

Run locally, outside the repository. OpenSSL prompts for a passphrase:

```sh
umask 077
ci_key_dir=$(mktemp -d)
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes-256-cbc -inform PEM -out "$ci_key_dir/rsa_key.p8"
openssl pkey -in "$ci_key_dir/rsa_key.p8" -pubout -out "$ci_key_dir/rsa_key.pub"
sed '/-----/d' "$ci_key_dir/rsa_key.pub" | tr -d '\n'
```

A Snowflake administrator registers the printed public key on the CI user. Use
the Snowflake user object's name in this SQL, which can differ from its login
name. A named key avoids replacing a key used by another integration:

```sql
ALTER USER <CI_USER> ADD KEY PAIR cms_alr_ci
  PUBLIC_KEY = '<PUBLIC_KEY_WITHOUT_HEADERS_OR_LINE_BREAKS>';
```

Upload the private key directly into GitHub, then enter the same passphrase at
the second command's hidden prompt:

```sh
gh secret set DBT_SNOWFLAKE_CI_PRIVATE_KEY --repo tuva-health/cms_alr_connector < "$ci_key_dir/rsa_key.p8"
gh secret set DBT_SNOWFLAKE_CI_PRIVATE_KEY_PASSPHRASE --repo tuva-health/cms_alr_connector
```

Keep key material out of commits, issues, PR comments, and logs. For key rotation,
register a new named key before updating GitHub and remove the old key only after
a successful CI run. See [Snowflake key-pair authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth).

## Rerunning checks

Pushes to a PR branch start the checks automatically. After changing only
secrets, rerun the failed job from the PR's Checks tab; a rerun uses the
original commit and workflow, and gets fresh schemas from its new attempt
number.
