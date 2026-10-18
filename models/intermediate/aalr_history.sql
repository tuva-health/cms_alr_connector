{% set exclude_cols = [
    'bene_mbi_id', 'bene_hic_num', 'bene_1st_name', 'bene_last_name',
    'bene_sex_cd', 'bene_brth_dt', 'bene_death_dt', 'geo_ssa_cnty_cd_name',
    'geo_ssa_state_name', 'state_county_cd', 'in_va_max', 'va_tin', 'va_npi',
    'cba_flag', 'assignment_type', 'assigned_before', 'asg_status', 'partd_months',
    'hcc_version', 'esrd_score', 'dis_score', 'agdu_score', 'agnd_score',
    'dem_esrd_score', 'dem_dis_score', 'dem_agdu_score', 'dem_agnd_score',
    'new_enrollee', 'lti_status', 'bene_race_cd', 'bene_psnyrs_dual',
    'directory_name', 'file_name', 'FILE_TYPE', 'FILE_PERIOD', 'PERFORMANCE_YEAR', 'ITERATION'
] %}
{% for i in range(1, 121) %}{% do exclude_cols.append('hcc_col_' ~ i) %}{% endfor %}
{% for i in range(1, 13) %}{% do exclude_cols.append('bene_rsk_r_scre_' ~ '%02d' % i) %}{% endfor %}

-- Unpivot enrollflag1–12 into one row per enrollment month per beneficiary
WITH aalr_unpivoted AS (
    {{ dbt_utils.unpivot(
        relation=ref('stg_aalr1_assigned_beneficiaries'),
        cast_to='integer',
        exclude=exclude_cols,
        field_name='enrollflag_name',
        value_name='enroll_flag'
    ) }}
),

-- Derive integer month_number from the enrollflag column name (e.g., 'enrollflag3' → 3)
aalr_exploded_by_enrollflag AS (
    SELECT
        CAST(REPLACE(LOWER(enrollflag_name), 'enrollflag', '') AS INTEGER) AS month_number,
        enroll_flag,
        bene_mbi_id,
        bene_hic_num,
        bene_1st_name,
        bene_last_name,
        bene_sex_cd,
        bene_brth_dt,
        bene_death_dt,
        geo_ssa_cnty_cd_name,
        geo_ssa_state_name,
        state_county_cd,
        in_va_max,
        va_tin,
        va_npi,
        cba_flag,
        assignment_type,
        assigned_before,
        asg_status,
        partd_months,
        hcc_version,
        {% for i in range(1, 121) %}
        hcc_col_{{ i }},
        {% endfor %}
        {% for i in range(1, 13) %}
        bene_rsk_r_scre_{{ '%02d' % i }},
        {% endfor %}
        esrd_score,
        dis_score,
        agdu_score,
        agnd_score,
        dem_esrd_score,
        dem_dis_score,
        dem_agdu_score,
        dem_agnd_score,
        new_enrollee,
        lti_status,
        bene_race_cd,
        bene_psnyrs_dual,
        directory_name,
        file_name,
        FILE_TYPE,
        FILE_PERIOD,
        PERFORMANCE_YEAR,
        ITERATION
    FROM aalr_unpivoted
),

-- Calculate enrollment month for each record based on the period the file is for and the month number from the enrollflag
add_calculated_month AS (
  SELECT
    CAST({{ dbt.dateadd('month', 'aalr.month_number - 1', 'mfp.period_start_date') }} AS DATE) AS enroll_month, -- Date add period_start_date + month number of flag - 1
    aalr.month_number,
    aalr.enroll_flag,
    aalr.bene_mbi_id,
    aalr.bene_hic_num,
    aalr.bene_1st_name,
    aalr.bene_last_name,
    aalr.bene_sex_cd,
    aalr.bene_brth_dt,
    aalr.bene_death_dt,
    aalr.geo_ssa_cnty_cd_name,
    aalr.geo_ssa_state_name,
    aalr.state_county_cd,
    aalr.in_va_max,
    aalr.va_tin,
    aalr.va_npi,
    aalr.cba_flag,
    aalr.assignment_type,
    aalr.assigned_before,
    aalr.asg_status,
    aalr.partd_months,
    aalr.hcc_version,
    {% for i in range(1, 121) %}
    aalr.hcc_col_{{ i }},
    {% endfor %}
    {% for i in range(1, 13) %}
    aalr.bene_rsk_r_scre_{{ '%02d' % i }},
    {% endfor %}
    aalr.esrd_score,
    aalr.dis_score,
    aalr.agdu_score,
    aalr.agnd_score,
    aalr.dem_esrd_score,
    aalr.dem_dis_score,
    aalr.dem_agdu_score,
    aalr.dem_agnd_score,
    aalr.new_enrollee,
    aalr.lti_status,
    aalr.bene_race_cd,
    aalr.bene_psnyrs_dual,
    aalr.directory_name,
    aalr.file_name,
    aalr.FILE_TYPE,
    aalr.FILE_PERIOD,
    aalr.PERFORMANCE_YEAR,
    aalr.ITERATION,
    mfp.report_year,
    mfp.period_start_date,
    mfp.period_end_date,
    mfp.priority,
    mfp.file_type as alr_file_type,
    {{ dbt.split_part('aalr.file_name', "'.'", 2) }} AS aco_id,
    {{ dbt.split_part('aalr.ITERATION', "'_'", 1) }} AS t_stamp
  FROM aalr_exploded_by_enrollflag as aalr
  LEFT JOIN {{ ref('mssp_file_parameters') }} as mfp ON aalr.PERFORMANCE_YEAR = mfp.PERFORMANCE_YEAR AND aalr.file_period = mfp.file_period
),

-- Rank each beneficiary's TINs (MASTER_ID) by E&M line count, and each TIN's
-- NPIs by PCS count, within one delivery: (aco_id, performance year, file
-- period, t_stamp), where t_stamp is ITERATION without its _1-<table> suffix,
-- as in aalr_governing_file (TUVA-108).
-- A plain row_number() + rn = 1, not dbt_utils.deduplicate: its default
-- implementation (used on DuckDB) re-joins the ranked rows with a NATURAL
-- JOIN on every column, and NULL = NULL never matches, so every row with a
-- blank column (BENE_HIC_NUM, BENE_DEATH_DT) dropped out (TUVA-112).
-- Ties on the count go to the lowest MASTER_ID / NPI_USED (our choice: CMS
-- breaks them on the most recent primary care service date, which the ALR
-- does not carry). NULLS LAST is explicit because Snowflake sorts NULLs first
-- on DESC and DuckDB last.
ranked_tin AS (
  SELECT
    tin.*,
    {{ dbt.split_part('tin.file_name', "'.'", 2) }} AS aco_id,
    {{ dbt.split_part('tin.ITERATION', "'_'", 1) }} AS t_stamp,
    row_number() OVER (
      PARTITION BY
        tin.BENE_MBI_ID,
        {{ dbt.split_part('tin.file_name', "'.'", 2) }},
        tin.PERFORMANCE_YEAR,
        tin.file_period,
        {{ dbt.split_part('tin.ITERATION', "'_'", 1) }}
      ORDER BY tin.B_EM_LINE_CNT_T DESC NULLS LAST, tin.MASTER_ID ASC NULLS LAST
    ) AS rn
  FROM {{ ref('stg_aalr2_assigned_beneficiaries_tin') }} AS tin
),

-- Filter to only the top MASTER_ID (TIN) based on EM counts
top_tin AS (
  SELECT * FROM ranked_tin WHERE rn = 1
),

ranked_npi AS (
  SELECT
    npi.*,
    {{ dbt.split_part('npi.file_name', "'.'", 2) }} AS aco_id,
    {{ dbt.split_part('npi.ITERATION', "'_'", 1) }} AS t_stamp,
    row_number() OVER (
      PARTITION BY
        npi.BENE_MBI_ID,
        {{ dbt.split_part('npi.file_name', "'.'", 2) }},
        npi.PERFORMANCE_YEAR,
        npi.file_period,
        {{ dbt.split_part('npi.ITERATION', "'_'", 1) }},
        npi.MASTER_ID
      ORDER BY npi.PCS_COUNT DESC NULLS LAST, npi.NPI_USED ASC NULLS LAST
    ) AS rn
  FROM {{ ref('stg_aalr4_assigned_beneficiaries_tin_npi') }} AS npi
),

-- Filter to only the top NPI for each Master_ID (TIN) based on PCS counts
top_npi AS (
  SELECT * FROM ranked_npi WHERE rn = 1
),

-- Get latest beneficiary turnover reason for the year (if a member leaves, comes back, and leaves again, we'll get the latest)
beneficiary_turnover AS (
  SELECT
    row_number() OVER(PARTITION BY bt.BENE_MBI_ID, bt.performance_year ORDER BY mfp.priority, bt.ITERATION DESC) AS row_number,
    bt.bene_mbi_id,
    bt.bene_hic_num,
    bt.bene_1st_name,
    bt.bene_last_name,
    bt.bene_sex_cd,
    bt.bene_brth_dt,
    bt.bene_death_dt,
    bt.plur_r05,
    bt.ab_r01,
    bt.hmo_r03,
    bt.no_us_r02,
    bt.mdm_r04,
    bt.nofnd_r06,
    bt.directory_name,
    bt.file_name,
    bt.FILE_TYPE,
    bt.FILE_PERIOD,
    bt.PERFORMANCE_YEAR,
    bt.ITERATION
  FROM {{ ref('stg_aalr5_beneficiary_turnover') }} as bt
  LEFT JOIN {{ ref('mssp_file_parameters') }} as mfp ON bt.PERFORMANCE_YEAR = mfp.PERFORMANCE_YEAR AND bt.file_period = mfp.file_period
),

latest_beneficiary_turnover AS (
  SELECT
    row_number,
    bene_mbi_id,
    bene_hic_num,
    bene_1st_name,
    bene_last_name,
    bene_sex_cd,
    bene_brth_dt,
    bene_death_dt,
    plur_r05,
    ab_r01,
    hmo_r03,
    no_us_r02,
    mdm_r04,
    nofnd_r06,
    directory_name,
    file_name,
    FILE_TYPE,
    FILE_PERIOD,
    PERFORMANCE_YEAR,
    ITERATION
  FROM beneficiary_turnover
  WHERE row_number = 1
)

SELECT
  row_number() OVER(PARTITION BY acm.BENE_MBI_ID, acm.enroll_month ORDER BY acm.performance_year, acm.priority, acm.ITERATION DESC) AS row_number,
  acm.enroll_month,
  acm.month_number,
  acm.enroll_flag,
  acm.bene_mbi_id,
  acm.bene_hic_num,
  acm.bene_1st_name,
  acm.bene_last_name,
  acm.bene_sex_cd,
  acm.bene_brth_dt,
  acm.bene_death_dt,
  acm.geo_ssa_cnty_cd_name,
  acm.geo_ssa_state_name,
  acm.state_county_cd,
  acm.in_va_max,
  acm.va_tin,
  acm.va_npi,
  acm.cba_flag,
  acm.assignment_type,
  acm.assigned_before,
  acm.asg_status,
  acm.partd_months,
  acm.hcc_version,
  {% for i in range(1, 121) %}
  acm.hcc_col_{{ i }},
  {% endfor %}
  {% for i in range(1, 13) %}
  acm.bene_rsk_r_scre_{{ '%02d' % i }},
  {% endfor %}
  acm.esrd_score,
  acm.dis_score,
  acm.agdu_score,
  acm.agnd_score,
  acm.dem_esrd_score,
  acm.dem_dis_score,
  acm.dem_agdu_score,
  acm.dem_agnd_score,
  acm.new_enrollee,
  acm.lti_status,
  acm.bene_race_cd,
  acm.bene_psnyrs_dual,
  acm.directory_name,
  acm.file_name,
  acm.FILE_TYPE,
  acm.FILE_PERIOD,
  acm.PERFORMANCE_YEAR,
  acm.ITERATION,
  acm.report_year,
  acm.period_start_date,
  acm.period_end_date,
  acm.priority,
  acm.alr_file_type,
  tt.MASTER_ID as TOP_TIN,
  tt.B_EM_LINE_CNT_T as TIN_EM_COUNT,
  tn.NPI_USED as TOP_NPI,
  tn.PCS_COUNT as NPI_EM_COUNT,
  baov.VA_SELECTION_ONLY,
  bu.ADI_NATRANK,
  bu.BENE_LIS_STATUS,
  bu.BENE_DUAL_STATUS,
  bu.BENE_PSNYRS_LIS_DUAL,
  bu.BENE_PSNYRS,
  lbt.plur_r05,
  lbt.ab_r01,
  lbt.hmo_r03,
  lbt.no_us_r02,
  lbt.mdm_r04,
  lbt.nofnd_r06
FROM add_calculated_month as acm
-- TIN and NPI come from the same delivery as the Table 1-1 row (TUVA-108), so
-- each row gets at most one of each, and in aalr_history_filtered they come
-- from the delivery that governs the month. A delivery without 1-2 / 1-4 rows
-- for the beneficiary leaves them NULL, even when an earlier one had them.
LEFT JOIN top_tin as tt
  ON acm.BENE_MBI_ID = tt.BENE_MBI_ID
  AND acm.aco_id = tt.aco_id
  AND acm.PERFORMANCE_YEAR = tt.PERFORMANCE_YEAR
  AND acm.FILE_PERIOD = tt.FILE_PERIOD
  AND acm.t_stamp = tt.t_stamp
LEFT JOIN top_npi AS tn
  ON acm.BENE_MBI_ID = tn.BENE_MBI_ID
  -- Only grab NPIs from the top TIN (it's possible an individual NPI NOT assigned to the top TIN has the most visits)
  AND tt.MASTER_ID = tn.MASTER_ID
  AND acm.aco_id = tn.aco_id
  AND acm.PERFORMANCE_YEAR = tn.PERFORMANCE_YEAR
  AND acm.FILE_PERIOD = tn.FILE_PERIOD
  AND acm.t_stamp = tn.t_stamp
-- Tables 1-6 and 1-9 likewise come from the Table 1-1 row's own delivery, so
-- a redelivered period doesn't multiply its rows (one per delivery).
LEFT JOIN {{ ref('stg_aalr6_beneficiaries_assignable_or_voluntary') }} as baov
  ON acm.BENE_MBI_ID = baov.BENE_MBI_ID
  AND acm.aco_id = {{ dbt.split_part('baov.file_name', "'.'", 2) }}
  AND acm.PERFORMANCE_YEAR = baov.PERFORMANCE_YEAR
  AND acm.FILE_PERIOD = baov.FILE_PERIOD
  AND acm.t_stamp = {{ dbt.split_part('baov.ITERATION', "'_'", 1) }}
LEFT JOIN {{ ref('stg_aalr9_beneficiaries_underserved')}} as bu
  ON acm.BENE_MBI_ID = bu.BENE_MBI_ID
  AND acm.aco_id = {{ dbt.split_part('bu.file_name', "'.'", 2) }}
  AND acm.PERFORMANCE_YEAR = bu.PERFORMANCE_YEAR
  AND acm.FILE_PERIOD = bu.FILE_PERIOD
  AND acm.t_stamp = {{ dbt.split_part('bu.ITERATION', "'_'", 1) }}
LEFT JOIN latest_beneficiary_turnover as lbt
  ON acm.BENE_MBI_ID = lbt.BENE_MBI_ID AND acm.performance_year = lbt.performance_year
