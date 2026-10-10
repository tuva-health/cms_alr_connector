{{ config(tags=['fixture', 'tuva-109']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A02b (TUVA-109): 9TT0FK2XX02 is assigned in 2025Q1,
    dropped in 2025Q2 (Table 1-5, NOFND_R06 = 1) and assigned again in 2025Q3.

    The 2025Q3 redelivery governs 2025-01..09 and lists the beneficiary, so it
    is enrolled in those nine months and none of those rows carries a turnover
    reason: the 2025Q2 drop-out is history, not its current status.
*/

with rows_2025 as (

    select
          enroll_month
        , plur_r05
        , ab_r01
        , hmo_r03
        , no_us_r02
        , mdm_r04
        , nofnd_r06
    from {{ ref('aalr_history_filtered') }}
    where bene_mbi_id = '9TT0FK2XX02'
      and enroll_month between cast('2025-01-01' as date) and cast('2025-09-01' as date)
      and enroll_flag > 0

)

select
      'turnover reason on a currently assigned row' as failure
    , enroll_month
from rows_2025
where coalesce(plur_r05, 0) + coalesce(ab_r01, 0) + coalesce(hmo_r03, 0)
    + coalesce(no_us_r02, 0) + coalesce(mdm_r04, 0) + coalesce(nofnd_r06, 0) > 0

union all

select
      'expected 9 enrolled months in 2025' as failure
    , cast(null as date) as enroll_month
from rows_2025
having count(distinct enroll_month) <> 9
