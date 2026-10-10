/*
    One row per beneficiary and enrollment month, taken from the ALR that
    governs the month (aalr_governing_file, TUVA-110). A beneficiary the
    governing file does not list has no row for that month, even when an
    earlier or later file lists them.

    Within the governing file, row_number = 1 keeps one row per beneficiary
    and month. aalr_history ranks each beneficiary's rows by (performance
    year, priority, ITERATION desc), and the governing file is by construction
    the first of those that covers the month, so its rows rank 1.

    The Table 1-5 reason flags (plur_r05 .. nofnd_r06) come from the governing
    file's own Table 1-5 (TUVA-109). They describe the beneficiary's status in
    the file that decides the month, not a drop-out from an earlier quarter,
    so a beneficiary assigned in the governing file carries none. aalr_history
    keeps the latest reason of the performance year on every row.
*/
WITH governing_turnover AS (
  SELECT
    bene_mbi_id,
    {{ dbt.split_part('file_name', "'.'", 2) }} AS aco_id,
    performance_year,
    file_period,
    {{ dbt.split_part('iteration', "'_'", 1) }} AS t_stamp,
    MAX(plur_r05) AS plur_r05,
    MAX(ab_r01) AS ab_r01,
    MAX(hmo_r03) AS hmo_r03,
    MAX(no_us_r02) AS no_us_r02,
    MAX(mdm_r04) AS mdm_r04,
    MAX(nofnd_r06) AS nofnd_r06
  FROM {{ ref('stg_aalr5_beneficiary_turnover') }}
  GROUP BY
    bene_mbi_id,
    {{ dbt.split_part('file_name', "'.'", 2) }},
    performance_year,
    file_period,
    {{ dbt.split_part('iteration', "'_'", 1) }}
)

SELECT
  ap.row_number,
  ap.enroll_month,
  ap.month_number,
  ap.enroll_flag,
  ap.bene_mbi_id,
  ap.bene_hic_num,
  ap.bene_1st_name,
  ap.bene_last_name,
  ap.bene_sex_cd,
  ap.bene_brth_dt,
  ap.bene_death_dt,
  ap.geo_ssa_cnty_cd_name,
  ap.geo_ssa_state_name,
  ap.state_county_cd,
  ap.in_va_max,
  ap.va_tin,
  ap.va_npi,
  ap.cba_flag,
  ap.assignment_type,
  ap.assigned_before,
  ap.asg_status,
  ap.partd_months,
  ap.hcc_version,
  {% for i in range(1, 121) %}
  ap.hcc_col_{{ i }},
  {% endfor %}
  {% for i in range(1, 13) %}
  ap.bene_rsk_r_scre_{{ '%02d' % i }},
  {% endfor %}
  ap.esrd_score,
  ap.dis_score,
  ap.agdu_score,
  ap.agnd_score,
  ap.dem_esrd_score,
  ap.dem_dis_score,
  ap.dem_agdu_score,
  ap.dem_agnd_score,
  ap.new_enrollee,
  ap.lti_status,
  ap.bene_race_cd,
  ap.bene_psnyrs_dual,
  ap.directory_name,
  ap.file_name,
  ap.FILE_TYPE,
  ap.FILE_PERIOD,
  ap.PERFORMANCE_YEAR,
  ap.ITERATION,
  ap.report_year,
  ap.period_start_date,
  ap.period_end_date,
  ap.priority,
  ap.alr_file_type,
  ap.TOP_TIN,
  ap.TIN_EM_COUNT,
  ap.TOP_NPI,
  ap.NPI_EM_COUNT,
  ap.VA_SELECTION_ONLY,
  ap.ADI_NATRANK,
  ap.BENE_LIS_STATUS,
  ap.BENE_DUAL_STATUS,
  ap.BENE_PSNYRS_LIS_DUAL,
  ap.BENE_PSNYRS,
  gt.plur_r05,
  gt.ab_r01,
  gt.hmo_r03,
  gt.no_us_r02,
  gt.mdm_r04,
  gt.nofnd_r06
FROM {{ ref('aalr_history')}} as ap
INNER JOIN {{ ref('aalr_governing_file') }} as gf
  ON ap.file_name = gf.file_name
  AND ap.enroll_month = gf.enroll_month
LEFT JOIN governing_turnover as gt
  ON ap.bene_mbi_id = gt.bene_mbi_id
  AND gf.aco_id = gt.aco_id
  AND gf.performance_year = gt.performance_year
  AND gf.file_period = gt.file_period
  AND gf.t_stamp = gt.t_stamp
WHERE ap.row_number = 1
