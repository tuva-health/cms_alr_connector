{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A01: a later quarterly ALR supersedes earlier ones.
    9TT0FK0XX01 has EnrollFlag 4 for 2025-01..03 in the 2025Q1 and 2025Q2
    ALRs and 3 (aged/dual) in 2025Q3, which was redelivered under T0310000.

    For 2025-01 to 2025-09 there is exactly one row per month, it comes from
    the 2025Q3 redelivery, and 2025-01..03 carry flag 3.
*/

with rows_2025 as (

    select
          enroll_month
        , enroll_flag
        , file_name
    from {{ ref('aalr_history_filtered') }}
    where bene_mbi_id = '9TT0FK0XX01'
      and enroll_month between cast('2025-01-01' as date) and cast('2025-09-01' as date)

)

select
      enroll_month
    , count(*) as row_count
    , min(enroll_flag) as min_flag
    , max(enroll_flag) as max_flag
    , min(file_name) as file_name
from rows_2025
group by enroll_month
having count(*) <> 1
    or max(file_name) not like '%.QALR.2025Q3.D259999.T0310000\_1-1.csv' escape '\'
    or (enroll_month <= cast('2025-03-01' as date) and max(enroll_flag) <> 3)
    or (enroll_month > cast('2025-03-01' as date) and max(enroll_flag) <> 4)

union all

select
      cast('2025-01-01' as date) as enroll_month
    , count(distinct enroll_month) as row_count
    , null as min_flag
    , null as max_flag
    , 'expected 9 months 2025-01..09' as file_name
from rows_2025
having count(distinct enroll_month) <> 9
