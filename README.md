[![Apache License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) ![dbt logo and version](https://img.shields.io/static/v1?logo=dbt&label=dbt-version&message=1.x&color=orange)

# Medicare ALR Connector

## 🔗 Docs
Check out our [docs](https://thetuvaproject.com/) to learn about the project and how you can use it.
<br/><br/>

## 🧰 What does this repo do?

The Medicare ALR Connector is a dbt package that maps raw Medicare Shared Savings Program Assignment List Report (ALR) data to the enrollment input required by the [Medicare CCLF Connector](https://github.com/tuva-health/medicare_cclf_connector). Together they map the input layer required to run the Tuva Project. This connector expects your ALR data to be organized into the tables outlined in this [CMS data dictionary](https://www.cms.gov/media/559411), which is the most recent format CMS uses to distribute ALR files.

Install it as a package in your own dbt project, as [cms_mssp_connector](https://github.com/tuva-health/cms_mssp_connector) does. It brings in the Medicare CCLF Connector (pinned to a commit) and, through it, the Tuva Project.
<br/><br/>  

## 🔌 Database Support

- DuckDB
- Snowflake

These are the warehouses CI builds on every pull request (see [integration_tests/README.md](integration_tests/README.md)).
<br/><br/>  

## ✅ Quickstart Guide

### Step 1: Install the package
Add the connector to your project's `packages.yml`, pinned to a commit (or, once releases exist, a tag), and run `dbt deps`:

```yaml
packages:
  - git: "https://github.com/tuva-health/cms_alr_connector.git"
    revision: <commit sha or tag>
```
<br/>

### Step 2: Data Preparation

#### Source data:
Load each ALR table into its own table, with every column landed as text. The connector reads six tables through `source('cms_ssp_reports', ...)`; their names are in `models/_sources.yml`:

| ALR table | Source table |
|---|---|
| 1-1 Assigned beneficiaries | `aalr1_assigned_beneficiaries` |
| 1-2 Beneficiary × participant TIN | `aalr2_assigned_beneficiaries_tin` |
| 1-4 Beneficiary × TIN × NPI | `aalr4_assigned_beneficiaries_tin_npi` |
| 1-5 Beneficiary turnover (quarterly only) | `aalr5_beneficiary_turnover` |
| 1-6 Assignable or voluntarily aligned | `aalr6_beneficiaries_assignable_or_voluntary` |
| 1-9 Underserved | `aalr9_beneficiaries_underserved` |

Each table has the CMS columns plus two columns your loader adds: `file_name` (see below) and `directory_name` (where the file came from; carried through, not parsed).

#### File format:
The ALR CSVs are comma-delimited with a header row whose field names are quoted. Strip the quotes from the column names when you load them. Land TINs, CCNs and NPIs (for example `va_tin`, `va_npi`, `master_id`, `npi_used`) as text: TINs and CCNs carry leading zeros that a numeric type drops, and the connector cannot restore them.

#### File name:
The field `file_name` is used throughout this connector to determine the performance year and report period of each row, which decide which file wins when several cover the same month. Set it to the per-table CSV's file name only, without the directory. The connector splits it on `.`:

| Report | `file_name` |
|---|---|
| Quarterly ALR | `P.A<ACO>.ACO.QALR.<PY>Q<n>.D<YY>9999.T<nnnnnnn>_1-<table>.csv`, e.g. `...QALR.2025Q3.D259999...` |
| Annual (benchmark) ALR | `P.A<ACO>.ACO.AALR.Y<yyyy>.D<YY>9999.T<nnnnnnn>_1-<table>.csv`, e.g. `...AALR.Y2023.D259999...` |

The fourth part is the report type (`QALR` or `AALR`) and the fifth the report period (`<PY>Q<n>` or `Y<yyyy>`). The two digits after `D` in the sixth part give the performance year (`D25…` is PY 2025). A name with no period part, `P.A<ACO>.ACO.AALR.D<YY>9999.T<nnnnnnn>_1-<table>.csv`, is read as the initial assignment for PY 20YY. The performance year and period are joined to the `mssp_file_parameters` seed, whose `priority` picks the file that wins: lower is preferred.

#### Risk scores:
CMS ships the CMS-HCC risk scores (`bene_rsk_r_scre_01` to `_12`, `esrd_score`, `dis_score`,
`agdu_score`, `agnd_score` and their `dem_*` counterparts) and the person-years fractions
(`bene_psnyrs_dual` in Table 1-1, `bene_psnyrs` and `bene_psnyrs_lis_dual` in Table 1-9) with up to
14 decimals. The connector keeps every one of those digits: the `cast_score` macro types these
columns as `numeric(38,14)`, on the staging models and all the way through to `enrollment` and
`aalr_history_filtered`. The Table 1-9 person-years are fractions of a year (for example 0.75 for 9
eligible months), not whole years. Counts and dollar amounts keep the `numeric(38,2)` of `cast_numeric`.
Land the score columns as text or as a numeric type with at least the decimals CMS publishes; a
source table that rounds them cannot be repaired here.

#### Birth and death dates:
CMS ships `BENE_BRTH_DT` and `BENE_DEATH_DT` in Tables 1-1, 1-2 and 1-4 to 1-6 as 10-character
`MM/DD/YYYY` text (ALR data dictionary). The connector parses them with that format on every
supported warehouse, so `bene_birth_date` and `bene_death_date` in `enrollment` are populated on
DuckDB as well as Snowflake; before, a plain cast left them NULL on DuckDB. Land these columns as text
exactly as CMS sends them. A value in any other format, such as an ISO `YYYY-MM-DD` date, reads as
NULL (our choice: the format is fixed by CMS, and guessing would accept day/month swaps silently).
<br/><br/>

### Step 3: Configure your project
Set these vars in your project's `dbt_project.yml`:

```yaml
vars:
  input_database: <database holding the raw ALR and CCLF tables>
  input_schema: <schema holding the raw ALR and CCLF tables>
  cms_alr_connector: true      # the CCLF connector takes enrollment from this connector
  demo_data_only: false        # see below
  claims_enabled: true
  provider_attribution_enabled: true
```

The connector always reads its tables through `source()` and ships no demo data. Earlier versions had a `demo_data_only` var that disabled the ALR sources; this connector no longer reads it. The Medicare CCLF Connector revision it pins still does and defaults it to `true`, which makes the CCLF connector read empty bundled seeds instead of your CCLF tables, so keep `demo_data_only: false` in your project until the pin moves to a CCLF release without the var. [integration_tests/dbt_project.yml](integration_tests/dbt_project.yml) lists every var the connector and its packages read.
<br/><br/> 

### Step 4: Run
Run the connector and the Tuva Project, for example with `dbt build` from your project's root folder.

Now you're ready to do claims data analytics!
<br/><br/>

## 🧪 Development

The `integration_tests` project installs this connector from the working tree, loads fixture seeds where `source()` expects the raw ALR and CCLF tables, and builds the connector against them. CI runs it on DuckDB and Snowflake. From the repo root, `scripts/dbt-local` runs dbt against it with the uv-locked toolchain; see [integration_tests/README.md](integration_tests/README.md).
<br/><br/>

## 🙋🏻‍♀️ How do I contribute?
Have an opinion on the mappings? Notice any bugs when installing and running the project?
If so, we highly encourage and welcome feedback!  While we work on a formal process in Github, we can be easily reached on our Slack community.
<br/><br/>

## 🤝 Join our community!
Join our growing community of healthcare data practitioners on [Slack](https://join.slack.com/t/thetuvaproject/shared_invite/zt-16iz61187-G522Mc2WGA2mHF57e0il0Q)!
