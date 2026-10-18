{{ config(tags=['fixture', 'tuva-121']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A13b (TUVA-121): provider attribution is keyed on the same
    person as eligibility. medicare_cclf_connector maps each ALR enrollment
    row's MBI to the current MBI through the CCLF9 crosswalk (seed
    beneficiary_xref), and the_tuva_project reads provider_attribution as it
    stands, so provider_attribution must already carry the current MBI.

    - Every (person_id, year_month) in provider_attribution is a crosswalked
      person-month of enrollment, and the other way round.
    - No person_id is a previous MBI in the crosswalk.
    - Each (person_id, year_month) appears once.
    - A13: 9TT0FK0XX14's PY2025 ALRs carry its previous MBI 9TT0FK0XX80, so
      its 2025-04..09 attribution rows come from those files and must sit under
      9TT0FK0XX14.
*/

with xref as (

    select distinct
          prvs_num
        , crnt_num
    from {{ source('medicare_cclf', 'beneficiary_xref') }}
    where prvs_num <> crnt_num

)

, eligibility_months as (

    select distinct
          coalesce(xref.crnt_num, enrollment.current_bene_mbi_id) as person_id
        , cast(enrollment.bene_member_month as {{ dbt.type_string() }}) as year_month
    from {{ ref('enrollment') }} as enrollment
    left join xref
        on enrollment.current_bene_mbi_id = xref.prvs_num

)

, attribution_months as (

    select
          person_id
        , year_month
        , count(*) as row_count
    from {{ ref('provider_attribution') }}
    group by
          person_id
        , year_month

)

select
      coalesce(eligibility_months.person_id, attribution_months.person_id) as person_id
    , coalesce(eligibility_months.year_month, attribution_months.year_month) as year_month
    , case
          when attribution_months.person_id is null then 'eligibility month without attribution'
          else 'attribution month without eligibility'
      end as failure
from eligibility_months
full outer join attribution_months
    on eligibility_months.person_id = attribution_months.person_id
   and eligibility_months.year_month = attribution_months.year_month
where eligibility_months.person_id is null or attribution_months.person_id is null

union all

select
      person_id
    , year_month
    , 'person_id is a previous MBI in the crosswalk' as failure
from attribution_months
where person_id in (select prvs_num from xref)

union all

select
      person_id
    , year_month
    , 'more than one attribution row for the person-month' as failure
from attribution_months
where row_count > 1

union all

select
      '9TT0FK0XX14' as person_id
    , null as year_month
    , 'expected 6 attribution months 202504..202509, got '
        || cast(count(*) as {{ dbt.type_string() }}) as failure
from attribution_months
where person_id = '9TT0FK0XX14'
  and year_month between '202504' and '202509'
having count(*) <> 6
