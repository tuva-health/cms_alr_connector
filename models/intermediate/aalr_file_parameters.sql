/*
    The parameters of every ALR file the connector can place (TUVA-164): one
    row per (performance_year, file_period, file_type), the key every model
    joins a file on (alr_file_type from extract_file_metadata is file_type).
    aalr_history (Table 1-1 and the Table 1-5 turnover lookup),
    aalr_governing_file and aalr_settlement_population read it instead of the
    mssp_file_parameters seed.

    It is the seed plus a derived row for each delivered benchmark AALR the
    seed has no row for. The seed's benchmark rows are BY1-BY3 = PY-3..PY-1,
    which holds only in the first performance year of an agreement period.
    Benchmark years are fixed for the whole agreement period
    (42 CFR 425.652(a)(9); methodology specifications section 4.1.3), and
    CMS's adjusted historical benchmark packages in later years ship an ALR
    for each of them (ALR/ASR User's Guide, Appendix Table 6). So an ACO past
    its first year gets AALR.Y<yyyy> files for earlier years than the seed
    has.

    A benchmark's parameters follow from its name alone: it covers calendar
    year <yyyy> (report_year <yyyy>), and its priority is the seed's benchmark
    priority, so it is last within its own performance year like any other
    benchmark. The month precedence is unchanged: the earliest performance
    year still wins, so a benchmark year re-delivered with a later
    performance year never displaces an earlier year's copy.

    No other file type is derived: quarterly and initial periods are not
    calendar years (PY2026's initial assignment covers 2024-10..2025-09). A
    file that matches neither a seed row nor a derived one is named by the
    alr_file_without_file_parameters test and reaches no model past staging.
*/

{#- The <yyyy> of a benchmark's Y<yyyy> period. -#}
{%- set benchmark_year = dbt.right('delivered_benchmarks.file_period', '4') -%}

with seed as (

    select
          performance_year
        , report_year
        , file_period
        , period_start_date
        , period_end_date
        , priority
        , file_type
    from {{ ref('mssp_file_parameters') }}

)

, benchmark_priority as (

    select max(priority) as priority
    from seed
    where file_type = 'benchmark'

)

, delivered_benchmarks as (

    select distinct
          cast(performance_year as {{ dbt.type_int() }}) as performance_year
        , file_period
    from {{ ref('stg_aalr1_assigned_beneficiaries') }}
    where alr_file_type = 'benchmark'

)

, derived as (

    select
          delivered_benchmarks.performance_year
        , cast({{ benchmark_year }} as {{ dbt.type_int() }}) as report_year
        , delivered_benchmarks.file_period
        , cast({{ dbt.concat([benchmark_year, "'-01-01'"]) }} as date) as period_start_date
        , cast({{ dbt.concat([benchmark_year, "'-12-31'"]) }} as date) as period_end_date
        , benchmark_priority.priority
        , 'benchmark' as file_type
    from delivered_benchmarks
    cross join benchmark_priority
    where not exists (
        select 1
        from seed
        where seed.performance_year = delivered_benchmarks.performance_year
          and seed.file_period = delivered_benchmarks.file_period
          and seed.file_type = 'benchmark'
    )

)

select
      performance_year
    , report_year
    , file_period
    , cast(period_start_date as date) as period_start_date
    , cast(period_end_date as date) as period_end_date
    , priority
    , file_type
    , 'seed' as parameter_source
from seed

union all

select
      performance_year
    , report_year
    , file_period
    , period_start_date
    , period_end_date
    , priority
    , file_type
    , 'derived' as parameter_source
from derived
