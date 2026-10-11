{{ config(tags=['fixture', 'tuva-109']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A02b (TUVA-109): 9TT0FK2XX02 is assigned in 2025Q1,
    dropped in 2025Q2 (Table 1-5, NOFND_R06 = 1) and assigned again in 2025Q3.

    The 2025Q3 redelivery governs 2025-01..09 and lists the beneficiary, so it
    is enrolled in those nine months and none of them carries a turnover
    reason: the 2025Q2 drop-out is history, not its current status.

    The reason for a month lives in the governing file's Table 1-5
    (aalr_governing_file joined to stg_aalr5_beneficiary_turnover), so that is
    where this checks. aalr_history_filtered must not carry the reason columns
    at all: they used to hold the performance year's latest reason on every
    row, which is how the 2025Q2 drop-out reached the assigned months.
*/

{%- set reason_columns = ['plur_r05', 'ab_r01', 'hmo_r03', 'no_us_r02', 'mdm_r04', 'nofnd_r06'] -%}
{%- set carried = [] -%}
{%- if execute -%}
    {%- for column in adapter.get_columns_in_relation(ref('aalr_history_filtered')) -%}
        {%- if column.name | lower in reason_columns -%}{%- do carried.append(column.name | lower) -%}{%- endif -%}
    {%- endfor -%}
{%- endif %}

with rows_2025 as (

    select distinct enroll_month
    from {{ ref('aalr_history_filtered') }}
    where bene_mbi_id = '9TT0FK2XX02'
      and enroll_month between cast('2025-01-01' as date) and cast('2025-09-01' as date)
      and enroll_flag > 0

)

, governing_turnover as (

    select
          gf.enroll_month
        , bt.plur_r05
        , bt.ab_r01
        , bt.hmo_r03
        , bt.no_us_r02
        , bt.mdm_r04
        , bt.nofnd_r06
    from {{ ref('aalr_governing_file') }} as gf
    inner join {{ ref('stg_aalr5_beneficiary_turnover') }} as bt
        on gf.aco_id = {{ dbt.split_part('bt.file_name', "'.'", 2) }}
       and gf.performance_year = bt.performance_year
       and gf.file_period = bt.file_period
       and gf.t_stamp = {{ dbt.split_part('bt.iteration', "'_'", 1) }}
    where bt.bene_mbi_id = '9TT0FK2XX02'

)

select
      'turnover reason on a currently assigned month' as failure
    , rows_2025.enroll_month
from rows_2025
inner join governing_turnover
    on rows_2025.enroll_month = governing_turnover.enroll_month
where coalesce(plur_r05, 0) + coalesce(ab_r01, 0) + coalesce(hmo_r03, 0)
    + coalesce(no_us_r02, 0) + coalesce(mdm_r04, 0) + coalesce(nofnd_r06, 0) > 0

union all

select
      'expected 9 enrolled months in 2025' as failure
    , cast(null as date) as enroll_month
from rows_2025
having count(*) <> 9

{%- for column in carried %}

union all

select
      'aalr_history_filtered carries turnover reason {{ column }}' as failure
    , cast(null as date) as enroll_month
{%- endfor %}
