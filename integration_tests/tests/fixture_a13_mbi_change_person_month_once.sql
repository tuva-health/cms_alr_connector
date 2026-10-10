{{ config(tags=['fixture', 'tuva-110']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A13 (TUVA-110): 9TT0FK0XX14's MBI changed (CCLF S14). The
    PY2025 ALRs carry the previous MBI 9TT0FK0XX80; PY2026's 2026Q1 carries
    the current one. Both cover 2025-04..09.

    After the CCLF9 crosswalk (seed beneficiary_xref), each person-month
    appears exactly once in enrollment, and the person is enrolled in every
    month 2023-10..2026-03. PY2025 governs 2025-04..09 (earliest performance
    year), so those months come from the previous MBI's 2025Q3 rows.
*/

with xref as (

    select distinct
          prvs_num
        , crnt_num
    from {{ source('medicare_cclf', 'beneficiary_xref') }}
    where prvs_num <> crnt_num

)

, person_months as (

    select
          coalesce(xref.crnt_num, enrollment.current_bene_mbi_id) as person_id
        , enrollment.current_bene_mbi_id
        , cast(enrollment.enrollment_start_date as date) as enroll_month
    from {{ ref('enrollment') }} as enrollment
    left join xref
        on enrollment.current_bene_mbi_id = xref.prvs_num
    where enrollment.current_bene_mbi_id in ('9TT0FK0XX14', '9TT0FK0XX80')

)

select
      enroll_month
    , count(*) as row_count
    , min(current_bene_mbi_id) as first_mbi
    , max(current_bene_mbi_id) as last_mbi
from person_months
where person_id = '9TT0FK0XX14'
group by enroll_month
having count(*) <> 1
    or (enroll_month between cast('2025-04-01' as date) and cast('2025-09-01' as date)
        and max(current_bene_mbi_id) <> '9TT0FK0XX80')

union all

select
      cast(null as date) as enroll_month
    , count(distinct enroll_month) as row_count
    , null as first_mbi
    , 'expected 30 months 2023-10..2026-03' as last_mbi
from person_months
where person_id = '9TT0FK0XX14'
having count(distinct enroll_month) <> 30
