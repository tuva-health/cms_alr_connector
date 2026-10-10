{{ config(tags=['fixture', 'tuva-108']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A08c (TUVA-108): 9TT0FK2XX11 is assigned in 2025Q3 (both
    deliveries). Its Table 1-2 rows tie on B_EM_LINE_CNT_T: 001000002 (5),
    then 001000001 (5). Under 001000001 its Table 1-4 rows tie on PCS_COUNT:
    1999900107 (4), then 1999900081 (4). 001000002 has 1999900099 (4).

    Our choice: the lowest MASTER_ID wins a TIN tie and the lowest NPI_USED an
    NPI tie, so every 2025-01..09 row has practice 001000001 and provider
    1999900081. The losing rows come first in the seeds, so a pick that
    depends on row order fails here.
*/

select
      year_month
    , payer_attributed_provider_practice
    , payer_attributed_provider
from {{ ref('provider_attribution') }}
where person_id = '9TT0FK2XX11'
  and (
        payer_attributed_provider_practice is null
     or payer_attributed_provider_practice <> '001000001'
     or payer_attributed_provider is null
     or payer_attributed_provider <> '1999900081'
  )

union all

select
      'expected 9 rows in 2025' as year_month
    , null as payer_attributed_provider_practice
    , null as payer_attributed_provider
from {{ ref('provider_attribution') }}
where person_id = '9TT0FK2XX11'
  and year_month between '202501' and '202509'
having count(*) <> 9
