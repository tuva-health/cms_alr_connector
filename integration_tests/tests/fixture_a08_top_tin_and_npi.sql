{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A08: 9TT0FK0XX23 has two TINs in Table 1-2 (EM line
    counts 7 for 001000001, 3 for 001000002) and three TIN-NPI rows in 1-4:
    001000001/1999900081 (PCS 5), 001000001/1999900107 (PCS 2) and
    001000002/1999900099 (PCS 9), in every ALR.

    Every provider_attribution row has practice 001000001 and provider
    1999900081: the top NPI of the top TIN, not the higher-PCS NPI that sits
    under the other TIN.
*/

select
      year_month
    , payer_attributed_provider_practice
    , payer_attributed_provider
from {{ ref('provider_attribution') }}
where person_id = '9TT0FK0XX23'
  and (
        payer_attributed_provider_practice is null
     or payer_attributed_provider_practice <> '001000001'
     or payer_attributed_provider is null
     or payer_attributed_provider <> '1999900081'
  )

union all

select
      'no rows' as year_month
    , null as payer_attributed_provider_practice
    , null as payer_attributed_provider
from {{ ref('provider_attribution') }}
where person_id = '9TT0FK0XX23'
having count(*) = 0
