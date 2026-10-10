/*
    One row per beneficiary and enrollment month, taken from the ALR that
    governs the month (aalr_governing_file, TUVA-110). A beneficiary the
    governing file does not list has no row for that month, even when an
    earlier or later file lists them.

    Within the governing file, row_number = 1 keeps one row per beneficiary
    and month. aalr_history ranks each beneficiary's rows by (performance
    year, priority, ITERATION desc), and the governing file is by construction
    the first of those that covers the month, so its rows rank 1.

    The Table 1-5 turnover reasons (plur_r05 .. nofnd_r06) are not carried
    here (TUVA-109). A beneficiary assigned in the governing file is never in
    that file's Table 1-5, so on these rows they could only ever be NULL; the
    performance year's latest reason stays on every row of aalr_history.
*/
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
  ap.BENE_PSNYRS
FROM {{ ref('aalr_history')}} as ap
INNER JOIN {{ ref('aalr_governing_file') }} as gf
  ON ap.file_name = gf.file_name
  AND ap.enroll_month = gf.enroll_month
WHERE ap.row_number = 1
