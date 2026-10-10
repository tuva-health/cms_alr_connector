{{ config(tags=['fixture', 'tuva-107']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A07 (TUVA-107, regression for TUVA-79): CMS ships CMS-HCC
    risk scores with 14 decimals. Quarterly ALRs fill ESRD/DIS/AGDU/AGND_SCORE;
    annual ALRs fill BENE_RSK_R_SCRE_01..12.

    9TT0FK0XX01  AGND_SCORE 1.23456789012345 in 2025Q3 (both deliveries), so
                 enrollment 2025-04..09; BENE_RSK_R_SCRE_01 0.87654321098765 in
                 AALR.Y2024, so enrollment 2024-01..06.

    Every digit reaches enrollment.
*/

select
      'agnd_score' as score
    , cast(enrollment_start_date as date) as enroll_month
    , agnd_score as actual
from {{ ref('enrollment') }}
where current_bene_mbi_id = '9TT0FK0XX01'
  and cast(enrollment_start_date as date) between cast('2025-04-01' as date) and cast('2025-09-01' as date)
  and (agnd_score is null or agnd_score <> cast('1.23456789012345' as decimal(38, 14)))

union all

select
      'bene_rsk_r_scre_01' as score
    , cast(enrollment_start_date as date) as enroll_month
    , bene_rsk_r_scre_01 as actual
from {{ ref('enrollment') }}
where current_bene_mbi_id = '9TT0FK0XX01'
  and cast(enrollment_start_date as date) between cast('2024-01-01' as date) and cast('2024-06-01' as date)
  and (bene_rsk_r_scre_01 is null
       or bene_rsk_r_scre_01 <> cast('0.87654321098765' as decimal(38, 14)))
