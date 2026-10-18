/*
    The ALR that governs each enrollment month, per ACO (TUVA-110).

    A file covers the twelve months its EnrollFlag1..12 map onto: from the
    period_start_date of its mssp_file_parameters row, up to period_end_date.
    Of the delivered files that cover a month, the governing one is picked in
    this order:
      1. the earliest performance year (a closed performance year is final);
      2. within it, the lowest mssp_file_parameters priority, i.e. the last of
         initial < Q1 < Q2 < Q3 < Q4 < benchmark;
      3. on a redelivery of the same period, the later T-stamp.

    Benchmark ALRs ship with the following performance year (PY2025 delivers
    Y2022..Y2024), so a benchmark governs only months no file from an earlier
    performance year covers; it is last only within its own performance year.

    The governing file alone decides a beneficiary's status for the month: a
    beneficiary it does not list is not enrolled that month, whatever other
    files say. It supplies all of the month's ALR-sourced fields (enrollment,
    risk scores and HCC flags, demographics, TIN/NPI attribution, Tables 1-6
    and 1-9). CCLF's data_sharing_flag comes from CCLF8 in
    medicare_cclf_connector and does not depend on it.

    One row per (aco_id, enroll_month). To take any ALR table from the
    governing file, join on (aco_id, performance_year, file_period, t_stamp),
    deriving aco_id and t_stamp from that table's file_name and ITERATION the
    same way as below.
*/

with delivered_files as (

    select distinct
          {{ dbt.split_part('file_name', "'.'", 2) }} as aco_id
        , performance_year
        , file_period
        , {{ dbt.split_part('iteration', "'_'", 1) }} as t_stamp
        , file_name
    from {{ ref('stg_aalr1_assigned_beneficiaries') }}

)

, month_numbers as (

    {{ dbt_utils.generate_series(12) }}

)

, file_months as (

    select
          delivered_files.aco_id
        , cast({{ dbt.dateadd('month', 'month_numbers.generated_number - 1', 'mfp.period_start_date') }} as date) as enroll_month
        , delivered_files.performance_year
        , delivered_files.file_period
        , delivered_files.t_stamp
        , delivered_files.file_name
        , mfp.performance_year as performance_year_number
        , mfp.priority
        , mfp.file_type as alr_file_type
    from delivered_files
    inner join {{ ref('mssp_file_parameters') }} as mfp
        on delivered_files.performance_year = mfp.performance_year
       and delivered_files.file_period = mfp.file_period
    cross join month_numbers
    where cast({{ dbt.dateadd('month', 'month_numbers.generated_number - 1', 'mfp.period_start_date') }} as date)
          <= cast(mfp.period_end_date as date)

)

, ranked as (

    select
          file_months.*
        , row_number() over (
            partition by aco_id, enroll_month
            order by performance_year_number, priority, t_stamp desc
          ) as governing_rank
    from file_months

)

select
      aco_id
    , enroll_month
    , performance_year
    , file_period
    , t_stamp
    , file_name
    , priority
    , alr_file_type
from ranked
where governing_rank = 1
