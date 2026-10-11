{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A08b: 9TT0FK2XX06 is assigned in 2025Q3 (both deliveries)
    but has no Table 1-2 or 1-4 rows. It is attributed for 2025-01..09 with no
    practice and no provider.
*/

select
      year_month
    , payer_attributed_provider_practice
    , payer_attributed_provider
from {{ ref('provider_attribution') }}
where person_id = '9TT0FK2XX06'
  and (payer_attributed_provider_practice is not null or payer_attributed_provider is not null)

union all

select
      'expected 9 rows in 2025' as year_month
    , null as payer_attributed_provider_practice
    , null as payer_attributed_provider
from {{ ref('provider_attribution') }}
where person_id = '9TT0FK2XX06'
  and year_month between '202501' and '202509'
having count(*) <> 9
