{{ config(tags=['fixture', 'tuva-107']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A09b (TUVA-107): Table 1-9 person-years are fractions of a
    year, written with up to 14 decimals.

    9TT0FK0XX21  eligible 9 of the 12 months of 2025Q3: BENE_PSNYRS 0.75.
    9TT0FK0XX07  BENE_PSNYRS 0.58333333333333 (7/12) in every ALR.

    The values reach aalr_history_filtered unchanged on the 2025-01..09 rows,
    which the 2025Q3 redelivery governs.
*/

select
      bene_mbi_id
    , enroll_month
    , bene_psnyrs
from {{ ref('aalr_history_filtered') }}
where enroll_month between cast('2025-01-01' as date) and cast('2025-09-01' as date)
  and enroll_flag > 0
  and (
        (bene_mbi_id = '9TT0FK0XX21'
         and (bene_psnyrs is null or bene_psnyrs <> cast('0.75' as decimal(38, 14))))
     or (bene_mbi_id = '9TT0FK0XX07'
         and (bene_psnyrs is null or bene_psnyrs <> cast('0.58333333333333' as decimal(38, 14))))
  )
