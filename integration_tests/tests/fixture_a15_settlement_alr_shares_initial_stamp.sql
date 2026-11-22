{{ config(tags=['fixture', 'tuva-152']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A15 (TUVA-152): the PY2025 settlement (STLMT) bundle's
    AALR, P.A0000.ACO.AALR.Y2025.D259999.T0000000_1-x.csv. Its period token
    Y2025 is its own performance year (a benchmark's is always earlier), and
    its stamp D259999.T0000000 is the HASSGN initial assignment's,
    P.A0000.ACO.AALR.D259999.T0000000_1-x.csv. Both parse to (A0000, 2025,
    Y2025, T0000000).

    1. Every ALR file is classified by alr_file_type: the settlement as
       settlement, the initial assignment as initial, AALR.Y2024 as benchmark,
       the QALRs as quarterly.
    2. The settlement has no mssp_file_parameters row (TUVA-113), so it has no
       aalr_history rows and governs no month.
    3. 9TT0FK2XX14 is in both files: TIN 001000001 / NPI 1999900081 in the
       initial file, TIN 001000002 (EM 20) / NPI 1999900099 and ADI_NATRANK 99
       in the settlement. The initial file's rows (2023-10..2024-09) come once
       per month and carry the initial file's own Table 1-2/1-4/1-9 values.
       (aalr_history's unique_combination_of_columns test covers uniqueness
       for every beneficiary.)
*/

with expected_type as (

    select 'P.A0000.ACO.AALR.Y2025.D259999.T0000000_1-1.csv' as file_name, 'settlement' as alr_file_type
    union all select 'P.A0000.ACO.AALR.D259999.T0000000_1-1.csv', 'initial'
    union all select 'P.A0000.ACO.AALR.Y2024.D259999.T1111111_1-1.csv', 'benchmark'
    union all select 'P.A0000.ACO.QALR.2025Q1.D259999.T0100000_1-1.csv', 'quarterly'
    union all select 'P.A0000.ACO.QALR.2025Q3.D259999.T0310000_1-1.csv', 'quarterly'
    union all select 'P.A0000.ACO.QALR.2026Q1.D269999.T0100000_1-1.csv', 'quarterly'

)

, staged_type as (

    select distinct file_name, alr_file_type
    from {{ ref('stg_aalr1_assigned_beneficiaries') }}

)

select
      'alr_file_type ' || coalesce(staged_type.alr_file_type, 'null') || ', expected ' || expected_type.alr_file_type as failure
    , expected_type.file_name
    , cast(null as date) as enroll_month
from expected_type
left join staged_type
    on expected_type.file_name = staged_type.file_name
where staged_type.alr_file_type is null
   or staged_type.alr_file_type <> expected_type.alr_file_type

union all

select
      'settlement row in aalr_history' as failure
    , file_name
    , enroll_month
from {{ ref('aalr_history') }}
where file_name = 'P.A0000.ACO.AALR.Y2025.D259999.T0000000_1-1.csv'

union all

select
      'initial-file row not from its own delivery: tin ' || coalesce(top_tin, 'null')
        || ', npi ' || coalesce(top_npi, 'null')
        || ', adi ' || coalesce(cast(adi_natrank as {{ dbt.type_string() }}), 'null') as failure
    , file_name
    , enroll_month
from {{ ref('aalr_history') }}
where bene_mbi_id = '9TT0FK2XX14'
  and file_name = 'P.A0000.ACO.AALR.D259999.T0000000_1-1.csv'
  and (
        coalesce(top_tin, '') <> '001000001'
     or coalesce(top_npi, '') <> '1999900081'
     or coalesce(cast(adi_natrank as {{ dbt.type_string() }}), '') = '99'
  )

union all

select
      'expected 12 initial-file rows, one per month' as failure
    , 'P.A0000.ACO.AALR.D259999.T0000000_1-1.csv' as file_name
    , cast(null as date) as enroll_month
from {{ ref('aalr_history') }}
where bene_mbi_id = '9TT0FK2XX14'
  and file_name = 'P.A0000.ACO.AALR.D259999.T0000000_1-1.csv'
having count(*) <> 12 or count(distinct enroll_month) <> 12
