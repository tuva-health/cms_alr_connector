{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A11: an initial-assignment (HASSGN) ALR, named per the
    README pattern without a period token: P.A0000.ACO.AALR.D259999.T0000000_1-1.csv.
    extract_file_metadata reads it as FILE_PERIOD Y2025, performance year 2025,
    which mssp_file_parameters maps to the initial window 2023-10..2024-09.

    9TT0FK2XX10 is listed only there (and in 2025Q1's Table 1-5). It is
    enrolled exactly 2023-10..12: AALR.Y2024 (the benchmark, which governs
    every month it covers) governs 2024 and does not list it.
*/

{{ fixture_enrollment_months_diff('A11', '9TT0FK2XX10', [('2023-10-01', '2023-12-01')]) }}

union all

select
      'A11' as scenario
    , bene_mbi_id
    , cast(null as date) as enroll_month
    , 'file metadata ' || coalesce(file_period, 'null') || '/' || coalesce(cast(performance_year as {{ dbt.type_string() }}), 'null') as failure
from {{ ref('stg_aalr1_assigned_beneficiaries') }}
where file_name = 'P.A0000.ACO.AALR.D259999.T0000000_1-1.csv'
  and (coalesce(file_period, '') <> 'Y2025' or cast(performance_year as {{ dbt.type_string() }}) <> '2025')
