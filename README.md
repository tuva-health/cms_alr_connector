[![Apache License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) ![dbt logo and version](https://img.shields.io/static/v1?logo=dbt&label=dbt-version&message=1.x&color=orange)

# Medicare ALR Connector

## 🔗 Docs
Check out our [docs](https://thetuvaproject.com/) to learn about the project and how you can use it.
<br/><br/>

## 🧰 What does this repo do?

The Medicare ALR Connector is a dbt project that maps raw Medicare ALR report data to the enrollment input required by the Medicare CCLF connector, together they can be used to map the input layer required to run the Tuva Project.  This connector expects your ALR data to be organized into the tables outlined in this [CMS data dictionary](https://www.cms.gov/media/559411), which is the most recent format CMS uses to distribute ALR files.
<br/><br/>  

## 🔌 Database Support

- BigQuery
- Databricks
- Fabric
- MotherDuck
- Redshift
- Snowflake
<br/><br/>  

## ✅ Quickstart Guide

### Step 1: Clone or Fork this Repository
Unlike [the Tuva Project](https://github.com/tuva-health/the_tuva_project), this repo is a dbt project, not a dbt package.  Clone or fork this repository to your local machine.
<br/><br/> 

### Step 2: Import the Medicare CCLF Connector repo
Next you need to import the Medicare CCLF repo into the Medicare ALR Connector dbt project.  For example, using dbt CLI you would `cd` into the directly where you cloned this project to and run `dbt deps` to import the latest version of the Medicare CCLF connector.
<br/><br/> 

### Step 3: Data Preparation

#### Source data:
The source table names the connector is expecting can be found in the 
`_sources.yml` config file. You can rename your source tables if needed or add an alias to the config. 

#### File Name:
The field `file_name` is used throughout this connector to determine the performance year,
and report period parameters that are required to accurately process the ALR files to determine
the latest enrollment records to be used. The filename for each individual file should be
parsed from the full file path (e.g. P.A****.ACO.AALR.DYY9999.T*******_*-*.csv)

#### Risk scores:
CMS ships the CMS-HCC risk scores (`bene_rsk_r_scre_01` to `_12`, `esrd_score`, `dis_score`,
`agdu_score`, `agnd_score` and their `dem_*` counterparts) and the dual-eligible person-years
fraction `bene_psnyrs_dual` with more than two decimals. The connector keeps those decimals: the
`cast_score` macro types these columns as `numeric(38,10)` (`BIGNUMERIC` on BigQuery), on the
staging model and all the way through to `enrollment`. Counts and dollar amounts keep the
`numeric(38,2)` of `cast_numeric`. Land the score columns as text or as a numeric type with at
least the decimals CMS publishes; a source table that rounds them cannot be repaired here.

### Step 4: Configure Input Database and Schema
Next you need to tell dbt where your Medicare ALR source data is located.  Do this using the variables `input_database` and `input_schema` in the `dbt_project.yml` file.  You also need to configure your `profile` in the `dbt_project.yml`.
<br/><br/> 

### Step 5: Run
Finally, run the connector and the Tuva Project. For example, using dbt CLI you would `cd` to the project root folder in the command line and execute `dbt build`.  

Now you're ready to do claims data analytics!
<br/><br/>

## 🙋🏻‍♀️ How do I contribute?
Have an opinion on the mappings? Notice any bugs when installing and running the project?
If so, we highly encourage and welcome feedback!  While we work on a formal process in Github, we can be easily reached on our Slack community.
<br/><br/>

## 🤝 Join our community!
Join our growing community of healthcare data practitioners on [Slack](https://join.slack.com/t/thetuvaproject/shared_invite/zt-16iz61187-G522Mc2WGA2mHF57e0il0Q)!
