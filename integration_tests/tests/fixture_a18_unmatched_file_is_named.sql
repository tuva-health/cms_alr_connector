{{ config(tags=['fixture', 'tuva-164']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A18 (TUVA-164): AALR.Y2026.D259999.T2222222, whose
    Y-year is after its performance year, so extract_file_metadata leaves
    alr_file_type NULL and no parameters row can match or be derived.

    1. The connector's alr_file_without_file_parameters test (warn in this
       project) names exactly this file, with performance year 2025, period
       Y2026 and a NULL type. A17's benchmark (AALR.Y2024.D289999) is not
       listed: its parameters are derived.
    2. The file reaches no model past staging: it has no aalr_history rows
       and governs no month.
*/

with named as (

    {{ cms_aalr_connector.alr_files_without_file_parameters() }}

)

, expected as (

    select
          'P.A0000.ACO.AALR.Y2026.D259999.T2222222' as delivery_id
        , '2025' as performance_year
        , 'Y2026' as file_period

)

select
      'unexpected file named: ' || named.delivery_id as failure
    , named.delivery_id
from named
left join expected
    on named.delivery_id = expected.delivery_id
   and cast(named.performance_year as {{ dbt.type_string() }}) = expected.performance_year
   and named.file_period = expected.file_period
   and named.alr_file_type is null
where expected.delivery_id is null

union all

select
      'expected file not named' as failure
    , expected.delivery_id
from expected
left join named
    on named.delivery_id = expected.delivery_id
where named.delivery_id is null

union all

select distinct
      'unmatched file in aalr_history' as failure
    , delivery_id
from {{ ref('aalr_history') }}
where delivery_id = 'P.A0000.ACO.AALR.Y2026.D259999.T2222222'

union all

select distinct
      'unmatched file governs a month' as failure
    , delivery_id
from {{ ref('aalr_governing_file') }}
where delivery_id = 'P.A0000.ACO.AALR.Y2026.D259999.T2222222'
