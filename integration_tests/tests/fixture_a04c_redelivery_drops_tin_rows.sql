{{ config(tags=['fixture', 'tuva-108']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A04c (TUVA-108): 2025Q3 T0300000 lists TIN 001000001 /
    NPI 1999900081 for 9TT0FK0XX05 in Tables 1-2 and 1-4; the T0310000
    redelivery has no 1-2 or 1-4 rows for it.

    The redelivery governs 2025-01..09, so provider_attribution has no
    attributed practice or provider for those months. The TIN and NPI of the
    superseded delivery must not attach to the redelivered rows.
*/

select
      'attribution from a superseded delivery' as failure
    , year_month
    , payer_attributed_provider_practice
    , payer_attributed_provider
from {{ ref('provider_attribution') }}
where person_id = '9TT0FK0XX05'
  and year_month between '202501' and '202509'
  and (payer_attributed_provider_practice is not null or payer_attributed_provider is not null)

union all

select
      'expected 9 attribution rows in 2025' as failure
    , null as year_month
    , null as payer_attributed_provider_practice
    , null as payer_attributed_provider
from {{ ref('provider_attribution') }}
where person_id = '9TT0FK0XX05'
  and year_month between '202501' and '202509'
having count(*) <> 9
