{{ config(tags=['fixture', 'tuva-113']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A16 (TUVA-113): the PY2025 settlement AALR delivered
    twice, embargoed (AALR.Y2025.D259999.T0000000) and unembargoed
    (AALR.Y2025.D259999.T1111111).

    1. aalr_settlement_population has every Table 1-1 row of both deliveries
       (30 and 29 beneficiaries), on the PY2025 settlement period
       (2025-01-01..2025-12-31), and is_latest_delivery is true exactly on
       the T1111111 rows.
    2. 9TT0FK2XX14's T1111111 row carries that delivery's own values:
       bene_psnyrs 0.75 (Table 1-9), bene_rsk_r_scre_01 1.23456789012345
       (Table 1-1), TIN 001000002 / NPI 1999900099 (Tables 1-2/1-4), and
       ADI_NATRANK 3 (1-9) and VA_SELECTION_ONLY 0 (1-6), not the embargoed
       copy's 99 and 1 (A15): the two deliveries are not pooled.
    3. Baseline 9TT0FK0XX01 is in T0000000 only.
    4. A settlement AALR never governs a month and never reaches
       aalr_history (TUVA-113 decision: it is exposed only as the
       settlement population).
*/

with expected_delivery as (

    select 'P.A0000.ACO.AALR.Y2025.D259999.T0000000' as delivery_id, 30 as beneficiaries, false as is_latest_delivery
    union all select 'P.A0000.ACO.AALR.Y2025.D259999.T1111111', 29, true

)

, population as (

    select * from {{ ref('aalr_settlement_population') }}

)

, actual_delivery as (

    select
          delivery_id
        , count(*) as beneficiaries
        , min(cast(is_latest_delivery as integer)) as min_latest
        , max(cast(is_latest_delivery as integer)) as max_latest
        , min(performance_year) as min_performance_year
        , max(performance_year) as max_performance_year
        , min(period_start_date) as period_start_date
        , max(period_end_date) as period_end_date
    from population
    group by delivery_id

)

select
      'settlement delivery: ' || coalesce(cast(actual_delivery.beneficiaries as {{ dbt.type_string() }}), 'no')
        || ' rows, expected ' || cast(expected_delivery.beneficiaries as {{ dbt.type_string() }}) as failure
    , expected_delivery.delivery_id
    , cast(null as {{ dbt.type_string() }}) as bene_mbi_id
from expected_delivery
left join actual_delivery
    on expected_delivery.delivery_id = actual_delivery.delivery_id
where actual_delivery.delivery_id is null
   or actual_delivery.beneficiaries <> expected_delivery.beneficiaries
   or actual_delivery.min_latest <> cast(expected_delivery.is_latest_delivery as integer)
   or actual_delivery.max_latest <> cast(expected_delivery.is_latest_delivery as integer)
   or actual_delivery.min_performance_year <> '2025'
   or actual_delivery.max_performance_year <> '2025'
   or actual_delivery.period_start_date <> cast('2025-01-01' as date)
   or actual_delivery.period_end_date <> cast('2025-12-31' as date)

union all

select
      'unexpected settlement delivery' as failure
    , actual_delivery.delivery_id
    , cast(null as {{ dbt.type_string() }}) as bene_mbi_id
from actual_delivery
left join expected_delivery
    on actual_delivery.delivery_id = expected_delivery.delivery_id
where expected_delivery.delivery_id is null

union all

select
      'latest settlement row not from its own delivery: psnyrs ' || coalesce(cast(bene_psnyrs as {{ dbt.type_string() }}), 'null')
        || ', score ' || coalesce(cast(bene_rsk_r_scre_01 as {{ dbt.type_string() }}), 'null')
        || ', tin ' || coalesce(top_tin, 'null')
        || ', npi ' || coalesce(top_npi, 'null')
        || ', adi ' || coalesce(cast(adi_natrank as {{ dbt.type_string() }}), 'null')
        || ', va ' || coalesce(va_selection_only, 'null') as failure
    , delivery_id
    , bene_mbi_id
from population
where bene_mbi_id = '9TT0FK2XX14'
  and is_latest_delivery
  and (
        bene_psnyrs is null or bene_psnyrs <> 0.75
     or bene_rsk_r_scre_01 is null or bene_rsk_r_scre_01 <> 1.23456789012345
     or coalesce(top_tin, '') <> '001000002'
     or coalesce(top_npi, '') <> '1999900099'
     or coalesce(cast(adi_natrank as {{ dbt.type_string() }}), '') <> '3'
     or coalesce(va_selection_only, '') <> '0'
  )

union all

select
      'expected one latest settlement row for 9TT0FK2XX14' as failure
    , 'P.A0000.ACO.AALR.Y2025.D259999.T1111111' as delivery_id
    , '9TT0FK2XX14' as bene_mbi_id
from population
where bene_mbi_id = '9TT0FK2XX14'
  and is_latest_delivery
having count(*) <> 1

union all

select
      'baseline listed outside the embargoed settlement' as failure
    , delivery_id
    , bene_mbi_id
from population
where bene_mbi_id = '9TT0FK0XX01'
  and delivery_id <> 'P.A0000.ACO.AALR.Y2025.D259999.T0000000'

union all

select
      'expected baseline in the embargoed settlement' as failure
    , 'P.A0000.ACO.AALR.Y2025.D259999.T0000000' as delivery_id
    , '9TT0FK0XX01' as bene_mbi_id
from population
where bene_mbi_id = '9TT0FK0XX01'
having count(*) <> 1

union all

select
      'settlement governs ' || cast(enroll_month as {{ dbt.type_string() }}) as failure
    , delivery_id
    , cast(null as {{ dbt.type_string() }}) as bene_mbi_id
from {{ ref('aalr_governing_file') }}
where alr_file_type = 'settlement'

union all

select
      'settlement row in aalr_history' as failure
    , delivery_id
    , bene_mbi_id
from {{ ref('aalr_history') }}
where alr_file_type = 'settlement'
