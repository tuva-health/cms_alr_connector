{{ config(tags=['fixture', 'tuva-106']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A06 (TUVA-106): deceased beneficiaries. CMS ships
    BENE_BRTH_DT and BENE_DEATH_DT as MM/DD/YYYY. EnrollFlag is non-zero
    through the death month and 0 after it.

    9TT0FK2XX05  died 2025-05-14 (shown from 2025Q2): enrolled 2023-10..2025-05.
    9TT0FK0XX20  died 2025-11-18 (shown in 2026Q1; CCLF S20): enrolled
                 2023-10..2025-11.

    Both are enrolled exactly through the death month, every enrollment row
    has a birth date, and the rows from reports that show the death carry the
    death date.
*/

{{ fixture_enrollment_months_diff('A06', '9TT0FK2XX05', [('2023-10-01', '2025-05-01')]) }}
union all
{{ fixture_enrollment_months_diff('A06', '9TT0FK0XX20', [('2023-10-01', '2025-11-01')]) }}
union all
select
      'A06' as scenario
    , current_bene_mbi_id as bene_mbi_id
    , cast(enrollment_start_date as date) as enroll_month
    , case
        when bene_birth_date is null then 'birth date null'
        else 'death date missing or wrong'
      end as failure
from {{ ref('enrollment') }}
where current_bene_mbi_id in ('9TT0FK2XX05', '9TT0FK0XX20')
  and (
        bene_birth_date is null
     or (current_bene_mbi_id = '9TT0FK2XX05'
         and cast(enrollment_start_date as date) >= cast('2025-01-01' as date)
         and (bene_death_date is null or bene_death_date <> cast('2025-05-14' as date)))
     or (current_bene_mbi_id = '9TT0FK0XX20'
         and cast(enrollment_start_date as date) >= cast('2025-10-01' as date)
         and (bene_death_date is null or bene_death_date <> cast('2025-11-18' as date)))
  )
