{{ config(tags=['fixture', 'tuva-110']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Month precedence (TUVA-110), fixture scenarios A02, A03 and A01's 2024
    months. For each beneficiary-month the governing ALR is the latest-received
    file of the earliest performance year whose files cover the month. Within
    PY2025 the receipt order is initial < 2025Q1 < AALR.Y2024 (benchmark) <
    2025Q2 < 2025Q3 < the 2025Q3 redelivery (later T-stamp).

    9TT0FK0XX01 (A01/A03): 2024-01..06 from AALR.Y2024, 2024-07..09 from
                 2025Q2, 2024-10..2025-09 from the 2025Q3 redelivery.
    9TT0FK2XX01 (A02): listed in the initial ALR, Y2024, 2025Q1 and 2025Q2,
                 dropped in 2025Q3: enrolled exactly 2023-10..2024-09.
    9TT0FK2XX03 (A03): listed in 2025Q1-Q3 but not in AALR.Y2024: enrolled
                 exactly 2024-07..2025-09 (Y2024 governs 2024-04..06).
*/

with expected_files as (

    select
          cast(spine.date_month as date) as enroll_month
        , case
            when cast(spine.date_month as date) <= cast('2024-06-01' as date) then '%.AALR.Y2024.D259999.T1111111\_1-1.csv'
            when cast(spine.date_month as date) <= cast('2024-09-01' as date) then '%.QALR.2025Q2.D259999.T0200000\_1-1.csv'
            else '%.QALR.2025Q3.D259999.T0310000\_1-1.csv'
          end as expected_file_pattern
    from (
        {{ dbt_utils.date_spine(
            datepart="month",
            start_date="cast('2024-01-01' as date)",
            end_date="cast('2025-10-01' as date)"
        ) }}
    ) as spine

)

, baseline_files as (

    select
          'A01/A03' as scenario
        , '9TT0FK0XX01' as bene_mbi_id
        , expected_files.enroll_month
        , coalesce(max(enrollment.file_name), 'no enrollment row') as failure
    from expected_files
    left join {{ ref('enrollment') }} as enrollment
        on enrollment.current_bene_mbi_id = '9TT0FK0XX01'
       and cast(enrollment.enrollment_start_date as date) = expected_files.enroll_month
    group by expected_files.enroll_month, expected_files.expected_file_pattern
    having count(enrollment.file_name) <> 1
        or max(enrollment.file_name) not like max(expected_files.expected_file_pattern) escape '\'

)

select * from baseline_files
union all
{{ fixture_enrollment_months_diff('A02', '9TT0FK2XX01', [('2023-10-01', '2024-09-01')]) }}
union all
{{ fixture_enrollment_months_diff('A03', '9TT0FK2XX03', [('2024-07-01', '2025-09-01')]) }}
