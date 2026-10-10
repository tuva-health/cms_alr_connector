[![Apache License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) ![dbt logo and version](https://img.shields.io/static/v1?logo=dbt&label=dbt-version&message=1.x&color=orange)

# Medicare ALR Connector

## 🔗 Docs
Check out our [docs](https://thetuvaproject.com/) to learn about the project and how you can use it.
<br/><br/>

## 🧰 What does this repo do?

The Medicare ALR Connector is a dbt package that maps raw Medicare Shared Savings Program Assignment List Report (ALR) data to the enrollment input required by the [Medicare CCLF Connector](https://github.com/tuva-health/medicare_cclf_connector). Together they map the input layer required to run the Tuva Project. This connector expects your ALR data to be organized into the tables outlined in this [CMS data dictionary](https://www.cms.gov/media/559411), which is the most recent format CMS uses to distribute ALR files.

Install it as a package in your own dbt project, as [cms_mssp_connector](https://github.com/tuva-health/cms_mssp_connector) does. It brings in the Medicare CCLF Connector (pinned to a commit) and, through it, the Tuva Project.
<br/><br/>  

## 🩺 Attributed practice and provider

`provider_attribution` gives each beneficiary-month a practice (TIN) and a provider (NPI) from the ALR file that governs that month:

- **Practice:** the ACO participant TIN with the most primary care services in Table 1-2 (`B_EM_LINE_CNT_T`).
- **Provider:** under that TIN, the individual NPI with the most primary care services in Table 1-4 (`PCS_COUNT`). An NPI with more services under a different TIN is not used.
- A beneficiary with no Table 1-2 or 1-4 rows has a NULL practice and provider. The ALR User's Guide, sections 1.2 and 1.4, says this happens for beneficiaries seen only at a CCN (FQHC, RHC, Method II CAH, ETA hospital) or assigned only through voluntary alignment.

These rules are our choice. CMS assigns a beneficiary to an ACO, not to a TIN or an NPI inside it, so the spec doesn't pick one.

Before v0.1.0, both columns were NULL for every beneficiary on DuckDB, because the TIN and NPI ranking dropped any row with a blank column such as `BENE_HIC_NUM` (TUVA-112). Snowflake was unaffected.
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

#### Which file decides each month:
Several ALRs cover the same months: the quarterly ALRs of a performance year overlap each other, the benchmark ALRs overlap the quarterlies, and the next performance year's reports overlap the current one. For each month the connector picks **one governing file** per ACO, and that file alone decides who is enrolled:

1. Take the **earliest performance year** with a file that covers the month. A closed performance year is final, so a later year's reports never rewrite it.
2. Within that year, take the **last file in the order initial < Q1 < Q2 < Q3 < Q4 < benchmark** (the `priority` column of `mssp_file_parameters`). The benchmark ALR is the final word on every month it covers.
3. If the same period was delivered more than once, the **later T-stamp** wins.

A file covers the twelve months its `EnrollFlag1`..`EnrollFlag12` map onto, counted from the file's `period_start_date` in `mssp_file_parameters`. **A beneficiary the governing file does not list is not enrolled for that month**, even if an earlier or later file lists them. For example, a beneficiary dropped from 2025Q3 is not enrolled in any 2025Q3 month, and one removed in a redelivery is not enrolled in the months it governs.

The CMS ALR documentation doesn't say how overlapping reports combine, so this rule is our choice. It replaces an earlier one that picked the earliest file per beneficiary, which kept such beneficiaries enrolled from a superseded file and, after an MBI change, could enroll the same person twice in a month. The governing file for each month is in the `aalr_governing_file` model.

The Table 1-5 turnover reasons (`plur_r05` .. `nofnd_r06`) in `aalr_history_filtered` come from the governing file's own Table 1-5, so they describe the beneficiary's status in that file. A beneficiary who dropped out in one quarter and is assigned again in the governing file carries no reason for those months. `aalr_history` still carries the performance year's latest reason on every row.

#### Risk scores:
CMS ships the CMS-HCC risk scores (`bene_rsk_r_scre_01` to `_12`, `esrd_score`, `dis_score`,
`agdu_score`, `agnd_score` and their `dem_*` counterparts) and the dual-eligible person-years
fraction `bene_psnyrs_dual` with more than two decimals. The connector keeps those decimals: the
`cast_score` macro types these columns as `numeric(38,10)`, on the staging model and all the way
through to `enrollment`. Counts and dollar amounts keep the `numeric(38,2)` of `cast_numeric`.
Land the score columns as text or as a numeric type with at least the decimals CMS publishes; a
source table that rounds them cannot be repaired here.
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
