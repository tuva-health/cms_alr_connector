{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A05: EnrollFlag codes 0-4 (0 not eligible, 1 ESRD,
    2 disabled, 3 aged/dual, 4 aged/non-dual).

    9TT0FK0XX21  disabled (2) to 2025-03, 0 for 2025-04..06, aged non-dual (4)
                 from 2025-07: enrolled 2023-10..2025-03 and 2025-07..2026-03,
                 with flag 2 in 2025-01..03 and 4 in 2025-07..09.
    9TT0FK0XX04  ESRD (1) in every month: enrolled 2023-10..2026-03.
    9TT0FK0XX06  enroll_flag comes from the governing file: 2025-07..09 is 4
                 (2025Q3 governs) although 2026Q1 says 3 (see A12).
    9TT0FK0XX22  aged/dual (3), first assigned in 2026Q1: enrolled 2026-01..03.
*/

with flags as (

    -- enrollment's public enroll_flag, so the codes are checked where
    -- consumers read them.
    select
          current_bene_mbi_id as bene_mbi_id
        , enrollment_start_date as enroll_month
        , enroll_flag
    from {{ ref('enrollment') }}
    where current_bene_mbi_id in ('9TT0FK0XX21', '9TT0FK0XX04', '9TT0FK0XX22', '9TT0FK0XX06')

)

{{ fixture_enrollment_months_diff('A05', '9TT0FK0XX21', [('2023-10-01', '2025-03-01'), ('2025-07-01', '2026-03-01')]) }}
union all
{{ fixture_enrollment_months_diff('A05', '9TT0FK0XX04', [('2023-10-01', '2026-03-01')]) }}
union all
{{ fixture_enrollment_months_diff('A05', '9TT0FK0XX22', [('2026-01-01', '2026-03-01')]) }}
union all
select
      'A05' as scenario
    , bene_mbi_id
    , enroll_month
    , 'unexpected EnrollFlag ' || cast(enroll_flag as {{ dbt.type_string() }}) as failure
from flags
where (bene_mbi_id = '9TT0FK0XX21' and enroll_month between cast('2025-01-01' as date) and cast('2025-03-01' as date) and enroll_flag <> 2)
   or (bene_mbi_id = '9TT0FK0XX21' and enroll_month between cast('2025-07-01' as date) and cast('2025-09-01' as date) and enroll_flag <> 4)
   or (bene_mbi_id = '9TT0FK0XX04' and enroll_flag <> 1)
   or (bene_mbi_id = '9TT0FK0XX22' and enroll_flag <> 3)
   or (bene_mbi_id = '9TT0FK0XX06' and enroll_month between cast('2025-07-01' as date) and cast('2025-09-01' as date) and enroll_flag <> 4)
