{{ config(tags=['fixture', 'tuva-164']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A17 (TUVA-164): a benchmark AALR with no
    mssp_file_parameters row, P.A0000.ACO.AALR.Y2024.D289999.T1111111_1-x.csv
    (performance year 2028, benchmark year 2024). The seed has no
    (2028, Y2024, benchmark) row; aalr_file_parameters derives one (calendar
    2024, benchmark priority).

    1. None of the file's aalr_history rows has a NULL enroll_month, and none
       repeats per (beneficiary, month). Without a parameters row each
       beneficiary got 12 rows with a NULL enroll_month (up to v1.1.1).
    2. The file has 12 rows for 9TT0FK2XX15, one for each month of its
       benchmark year, calendar 2024.
    3. The file governs no month (PY2025's files cover 2024), so 9TT0FK2XX15,
       listed in it and in every PY2025 file, is enrolled exactly
       2023-10..2025-09.
*/

with a17_rows as (

    select bene_mbi_id, enroll_month
    from {{ ref('aalr_history') }}
    where file_name = 'P.A0000.ACO.AALR.Y2024.D289999.T1111111_1-1.csv'

)

, expected_months as (

    select cast({{ dbt.dateadd('month', 'generated_number - 1', "cast('2023-10-01' as date)") }} as date) as enroll_month
    from ({{ dbt_utils.generate_series(24) }}) as months

)

, enrolled as (

    select cast(enrollment_start_date as date) as enroll_month
    from {{ ref('enrollment') }}
    where current_bene_mbi_id = '9TT0FK2XX15'

)

select
      'NULL enroll_month in aalr_history' as failure
    , bene_mbi_id
    , cast(null as date) as enroll_month
from a17_rows
where enroll_month is null

union all

select
      'aalr_history row repeated ' || cast(count(*) as {{ dbt.type_string() }}) || ' times' as failure
    , bene_mbi_id
    , enroll_month
from a17_rows
group by bene_mbi_id, enroll_month
having count(*) > 1

union all

select
      'enroll_month outside benchmark year 2024' as failure
    , bene_mbi_id
    , enroll_month
from a17_rows
where enroll_month < cast('2024-01-01' as date)
   or enroll_month > cast('2024-12-01' as date)

union all

select
      'expected 12 aalr_history rows, one per month of 2024' as failure
    , '9TT0FK2XX15' as bene_mbi_id
    , cast(null as date) as enroll_month
from a17_rows
having count(*) <> 12 or count(distinct enroll_month) <> 12

union all

select
      'missing enrollment month' as failure
    , '9TT0FK2XX15' as bene_mbi_id
    , expected_months.enroll_month
from expected_months
left join enrolled
    on expected_months.enroll_month = enrolled.enroll_month
where enrolled.enroll_month is null

union all

select
      'unexpected enrollment month' as failure
    , '9TT0FK2XX15' as bene_mbi_id
    , enrolled.enroll_month
from enrolled
left join expected_months
    on enrolled.enroll_month = expected_months.enroll_month
where expected_months.enroll_month is null
