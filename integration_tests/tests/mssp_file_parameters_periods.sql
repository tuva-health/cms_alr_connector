{{ config(tags=['tuva-111']) }}

-- Depend on the model that reads the seed, not on the seed alone. CI's build
-- excludes package:integration_tests,resource_type:seed, and that selector
-- also catches an integration test whose only parent is a seed.
-- depends_on: {{ ref('aalr_history') }}

/*
    Seed check (TUVA-111): aalr_history maps EnrollFlag1..12 onto months from a
    file's period_start_date, so every mssp_file_parameters row must cover
    exactly 12 months, from the first of a month to the last day of the 12th.
    A benchmark (AALR Y<yyyy>) row covers calendar year report_year. A
    settlement row (TUVA-113) covers its own calendar performance year and has
    no priority, since it never governs a month; every other row has one.

    No fixture delivers a PY2026 Y2025 benchmark, so this checks the seed itself.
*/

with params as (
    select
          performance_year
        , report_year
        , file_period
        , file_type
        , priority
        , cast(period_start_date as date) as period_start_date
        , cast(period_end_date as date) as period_end_date
    from {{ ref('mssp_file_parameters') }}
)

select
      performance_year
    , file_period
    , period_start_date
    , period_end_date
    , 'period is not 12 whole months' as failure
from params
where extract(day from period_start_date) <> 1
   or cast({{ dbt.dateadd('day', -1, dbt.dateadd('month', 12, 'period_start_date')) }} as date)
      <> period_end_date

union all

select
      performance_year
    , file_period
    , period_start_date
    , period_end_date
    , 'benchmark period is not calendar report_year' as failure
from params
where file_type = 'benchmark'
  and (
        extract(year from period_start_date) <> report_year
     or extract(month from period_start_date) <> 1
  )

union all

select
      performance_year
    , file_period
    , period_start_date
    , period_end_date
    , 'settlement period is not calendar performance_year, or has a priority' as failure
from params
where file_type = 'settlement'
  and (
        extract(year from period_start_date) <> performance_year
     or extract(month from period_start_date) <> 1
     or report_year <> performance_year
     or priority is not null
  )

union all

select
      performance_year
    , file_period
    , period_start_date
    , period_end_date
    , 'governing file type without a priority' as failure
from params
where file_type <> 'settlement'
  and priority is null
