{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A09: Table 1-6 lists every assigned beneficiary
    (VA_SELECTION_ONLY 0), two assignable-only beneficiaries that no 1-1 lists
    (9TT0FK2XX07, 9TT0FK2XX08), and one voluntarily aligned beneficiary,
    9TT0FK2XX09 (IN_VA_MAX 1, VA_SELECTION_ONLY 1).

    The assignable-only beneficiaries are never enrolled, and 9TT0FK2XX09's
    enrolled rows carry va_selection_only = '1'.
*/

select
      'assignable-only beneficiary enrolled' as failure
    , current_bene_mbi_id as bene_mbi_id
    , cast(enrollment_start_date as date) as enroll_month
from {{ ref('enrollment') }}
where current_bene_mbi_id in ('9TT0FK2XX07', '9TT0FK2XX08')

union all

select
      'va_selection_only not carried' as failure
    , bene_mbi_id
    , enroll_month
from {{ ref('aalr_history_filtered') }}
where bene_mbi_id = '9TT0FK2XX09'
  and enroll_flag > 0
  and coalesce(va_selection_only, '') <> '1'

union all

select
      'voluntarily aligned beneficiary not enrolled' as failure
    , '9TT0FK2XX09' as bene_mbi_id
    , cast(null as date) as enroll_month
from {{ ref('enrollment') }}
where current_bene_mbi_id = '9TT0FK2XX09'
having count(*) = 0
