{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A04: 2025Q3 is redelivered under a later T-stamp
    (T0310000) with a corrected AGND_SCORE for 9TT0FK0XX02.

    Every beneficiary-month appears once in enrollment, and 9TT0FK0XX02's 2025
    rows carry the redelivered score 1.07654321098765, not the T0300000 value
    1.01234567890123. (Full 14-decimal precision is TUVA-107's test, A07; this
    one tolerates the current 10 decimals.)
*/

select
      'duplicate beneficiary-month' as failure
    , current_bene_mbi_id
    , cast(enrollment_start_date as date) as enroll_month
from {{ ref('enrollment') }}
group by current_bene_mbi_id, cast(enrollment_start_date as date)
having count(*) > 1

union all

select
      'not the redelivered AGND_SCORE' as failure
    , current_bene_mbi_id
    , cast(enrollment_start_date as date) as enroll_month
from {{ ref('enrollment') }}
where current_bene_mbi_id = '9TT0FK0XX02'
  and cast(enrollment_start_date as date) between cast('2025-01-01' as date) and cast('2025-09-01' as date)
  and (agnd_score is null or abs(agnd_score - 1.07654321098765) > 0.000000001)
