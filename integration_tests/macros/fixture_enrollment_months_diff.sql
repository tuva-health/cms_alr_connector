{#-
    Fixture-test helper: compares the months a beneficiary is enrolled in
    `enrollment` with the months a scenario expects, over the fixture window
    2023-10 to 2026-03. Returns one row per month that is expected but missing
    or present but not expected.

    expected_months: list of (first_month, last_month) pairs, 'YYYY-MM-DD'.
-#}

{% macro fixture_enrollment_months_diff(scenario, bene_mbi_id, expected_months) %}

    select
          '{{ scenario }}' as scenario
        , '{{ bene_mbi_id }}' as bene_mbi_id
        , cast(spine.date_month as date) as enroll_month
        , case
            when actual.enroll_month is null then 'expected enrolled, missing'
            else 'enrolled, not expected'
          end as failure
    from (
        {{ dbt_utils.date_spine(
            datepart="month",
            start_date="cast('2023-10-01' as date)",
            end_date="cast('2026-04-01' as date)"
        ) }}
    ) as spine
    left join (
        select distinct cast(enrollment_start_date as date) as enroll_month
        from {{ ref('enrollment') }}
        where current_bene_mbi_id = '{{ bene_mbi_id }}'
    ) as actual
        on actual.enroll_month = cast(spine.date_month as date)
    where
        (case when (
            {%- for first, last in expected_months %}
            {% if not loop.first %}or {% endif %}cast(spine.date_month as date) between cast('{{ first }}' as date) and cast('{{ last }}' as date)
            {%- else %} 1 = 0 {%- endfor %}
        ) then 1 else 0 end)
        <> (case when actual.enroll_month is not null then 1 else 0 end)

{% endmacro %}
