{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A02: 9TT0FK2XX01 is assigned in 2025Q1 and 2025Q2,
    dropped in 2025Q3 and listed in 2025Q3's Table 1-5 with PLUR_R05 = 1 (as
    is the T0310000 redelivery).

    No enrollment from 2025-01 on (2025Q3 governs those months and does not
    list it), and its aalr_history rows carry plur_r05 = 1. Its 2023-2024
    months are asserted by fixture_month_precedence.
*/

select
      'enrolled after the drop-out' as failure
    , cast(enrollment_start_date as date) as enroll_month
from {{ ref('enrollment') }}
where current_bene_mbi_id = '9TT0FK2XX01'
  and cast(enrollment_start_date as date) >= cast('2025-01-01' as date)

union all

select
      'plur_r05 not carried' as failure
    , enroll_month
from {{ ref('aalr_history') }}
where bene_mbi_id = '9TT0FK2XX01'
  and coalesce(plur_r05, 0) <> 1
