{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A10: with cms_alr_connector true, medicare_cclf_connector
    takes enrollment from this connector's `enrollment` model (the pinned
    revision's stg_enrollment selects it unchanged). The ALR fixtures cover the
    same beneficiaries as the CCLF fixtures (9TT0FK0XX01-28), so after the
    CCLF9 crosswalk (seed beneficiary_xref) their member months in 2025-01 to
    2026-02 match the CCLF fixtures' enrollment:

    - every month 2025-01..2026-02, except
    - 9TT0FK0XX20 (deceased 2025-11-18): through 2025-11
    - 9TT0FK0XX21 (gap): not 2025-04..06
    - 9TT0FK0XX22 (first seen in CY26): 2026-01..02 only

    9TT0FK0XX14's 2025 ALRs carry its previous MBI (CCLF S14); the crosswalk
    maps it. This test checks months only; one row per person-month is A13's.
    It reads `enrollment` rather than the CCLF models so that it runs in the
    connector-scope CI job, which does not build medicare_cclf_connector.
*/

with xref as (

    select distinct
          prvs_num
        , crnt_num
    from {{ source('medicare_cclf', 'beneficiary_xref') }}
    where prvs_num <> crnt_num

)

, alr_months as (

    select distinct
          coalesce(xref.crnt_num, enrollment.current_bene_mbi_id) as person_id
        , cast(enrollment.enrollment_start_date as date) as enroll_month
    from {{ ref('enrollment') }} as enrollment
    left join xref
        on enrollment.current_bene_mbi_id = xref.prvs_num
    where cast(enrollment.enrollment_start_date as date)
          between cast('2025-01-01' as date) and cast('2026-02-01' as date)

)

, persons as (

    select distinct person_id
    from alr_months
    where person_id like '9TT0FK0XX%'

)

, months as (

    select cast(date_month as date) as enroll_month
    from (
        {{ dbt_utils.date_spine(
            datepart="month",
            start_date="cast('2025-01-01' as date)",
            end_date="cast('2026-03-01' as date)"
        ) }}
    ) as spine

)

, expected as (

    select
          persons.person_id
        , months.enroll_month
    from persons
    cross join months
    where not (persons.person_id = '9TT0FK0XX20' and months.enroll_month > cast('2025-11-01' as date))
      and not (persons.person_id = '9TT0FK0XX21'
               and months.enroll_month between cast('2025-04-01' as date) and cast('2025-06-01' as date))
      and not (persons.person_id = '9TT0FK0XX22' and months.enroll_month < cast('2026-01-01' as date))

)

select
      coalesce(expected.person_id, alr_months.person_id) as person_id
    , coalesce(expected.enroll_month, alr_months.enroll_month) as enroll_month
    , case when alr_months.person_id is null then 'missing month' else 'unexpected month' end as failure
from expected
full outer join (select * from alr_months where person_id like '9TT0FK0XX%') as alr_months
    on expected.person_id = alr_months.person_id
   and expected.enroll_month = alr_months.enroll_month
where expected.person_id is null or alr_months.person_id is null

union all

select
      'persons' as person_id
    , cast(null as date) as enroll_month
    , 'expected 28 CCLF fixture beneficiaries, got ' || cast(count(*) as {{ dbt.type_string() }}) as failure
from persons
having count(*) <> 28
