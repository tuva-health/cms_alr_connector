{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A12: PY2025's 2025Q3 and PY2026's 2026Q1 both cover
    2025-04..09. For 9TT0FK0XX06 2026Q1 says EnrollFlag 3 in 2025-07..09 and
    2025Q3 says 4.

    The earliest performance year that covers a month governs it: 2025-07..09
    come from PY2025 with flag 4. 2025-10..2026-03 are covered only by PY2026.
*/

select
      enroll_month
    , performance_year
    , enroll_flag
from {{ ref('aalr_history_filtered') }}
where bene_mbi_id = '9TT0FK0XX06'
  and (
        (enroll_month between cast('2025-04-01' as date) and cast('2025-09-01' as date)
         and (cast(performance_year as {{ dbt.type_string() }}) <> '2025' or enroll_flag <> 4))
     or (enroll_month >= cast('2025-10-01' as date)
         and cast(performance_year as {{ dbt.type_string() }}) <> '2026')
  )

union all

select
      cast('2025-07-01' as date) as enroll_month
    , null as performance_year
    , count(*) as enroll_flag
from {{ ref('aalr_history_filtered') }}
where bene_mbi_id = '9TT0FK0XX06'
  and enroll_month = cast('2025-07-01' as date)
having count(*) <> 1
