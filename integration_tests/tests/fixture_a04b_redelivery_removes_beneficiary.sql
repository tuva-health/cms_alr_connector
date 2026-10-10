{{ config(tags=['fixture', 'tuva-108']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A04b (TUVA-108): 9TT0FK2XX04 is listed in 2025Q3
    T0300000 but not in the T0310000 redelivery of the same period, which
    lists it in Table 1-5 instead.

    The redelivered file replaces the original as a whole, so the beneficiary
    has no enrollment in 2025-01..09.
*/

select
      'enrolled from a superseded delivery' as failure
    , cast(enrollment_start_date as date) as enroll_month
    , file_name
from {{ ref('enrollment') }}
where current_bene_mbi_id = '9TT0FK2XX04'
  and cast(enrollment_start_date as date) between cast('2025-01-01' as date) and cast('2025-09-01' as date)
