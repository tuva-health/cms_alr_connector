{#-
    Every delivered ALR file with no aalr_file_parameters row (TUVA-164): one
    row per delivery, with the performance year, period and alr_file_type
    parsed from its name (extract_file_metadata). Such a file has no period to
    map its EnrollFlag1..12 onto, so aalr_history, the turnover lookup and
    aalr_governing_file leave it out. aalr_settlement_population keeps its rows
    with a NULL period.

    Benchmark AALRs are never listed: aalr_file_parameters derives a row for
    every delivered benchmark. What remains is a quarterly or initial file for
    a performance year the seed doesn't cover yet, a settlement the seed has no
    row for, or a name extract_file_metadata can't classify (alr_file_type
    NULL). The fix is a mssp_file_parameters row in a connector release.

    Tables 1-1 and 1-5 are checked: they are the tables read through the
    parameters. Used by the alr_file_without_file_parameters test.
-#}
{% macro alr_files_without_file_parameters() %}

with delivered as (

    select distinct delivery_id, performance_year, file_period, alr_file_type
    from {{ ref('stg_aalr1_assigned_beneficiaries') }}

    union

    select distinct delivery_id, performance_year, file_period, alr_file_type
    from {{ ref('stg_aalr5_beneficiary_turnover') }}

)

select
      delivered.delivery_id
    , delivered.performance_year
    , delivered.file_period
    , delivered.alr_file_type
from delivered
left join {{ ref('aalr_file_parameters') }} as afp
    on cast(delivered.performance_year as {{ dbt.type_int() }}) = afp.performance_year
   and delivered.file_period = afp.file_period
   and delivered.alr_file_type = afp.file_type
where afp.file_type is null

{% endmacro %}
