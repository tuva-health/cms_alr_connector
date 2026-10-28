{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A14 (TUVA-134): an assigned disabled and an assigned
    aged/dual beneficiary, listed in every ALR delivery for the whole fixture
    window with a single EnrollFlag code, so the performance year 2025
    quarterly ALRs carry their type's risk score column.

    9TT0FK2XX12  disabled (2): enrolled 2023-10..2026-03, flag 2 every month;
                 2025-01..09 rows (2025Q3 redelivery) carry dis_score only.
    9TT0FK2XX13  aged/dual (3): enrolled 2023-10..2026-03, flag 3 every month;
                 2025-01..09 rows carry agdu_score only.
*/

with flags as (

    select
          bene_mbi_id
        , enroll_month
        , enroll_flag
    from {{ ref('aalr_history_filtered') }}
    where bene_mbi_id in ('9TT0FK2XX12', '9TT0FK2XX13')
      and enroll_flag > 0

)

, scores_2025 as (

    select
          current_bene_mbi_id as bene_mbi_id
        , cast(enrollment_start_date as date) as enroll_month
        , esrd_score
        , dis_score
        , agdu_score
        , agnd_score
    from {{ ref('enrollment') }}
    where current_bene_mbi_id in ('9TT0FK2XX12', '9TT0FK2XX13')
      and cast(enrollment_start_date as date) between cast('2025-01-01' as date) and cast('2025-09-01' as date)

)

{{ fixture_enrollment_months_diff('A14', '9TT0FK2XX12', [('2023-10-01', '2026-03-01')]) }}
union all
{{ fixture_enrollment_months_diff('A14', '9TT0FK2XX13', [('2023-10-01', '2026-03-01')]) }}
union all
select
      'A14' as scenario
    , bene_mbi_id
    , enroll_month
    , 'unexpected EnrollFlag ' || cast(enroll_flag as {{ dbt.type_string() }}) as failure
from flags
where (bene_mbi_id = '9TT0FK2XX12' and enroll_flag <> 2)
   or (bene_mbi_id = '9TT0FK2XX13' and enroll_flag <> 3)
union all
select
      'A14' as scenario
    , bene_mbi_id
    , enroll_month
    , 'risk score not in the enrollment type''s column' as failure
from scores_2025
where esrd_score is not null
   or agnd_score is not null
   or (bene_mbi_id = '9TT0FK2XX12' and (dis_score is null or agdu_score is not null))
   or (bene_mbi_id = '9TT0FK2XX13' and (agdu_score is null or dis_score is not null))
