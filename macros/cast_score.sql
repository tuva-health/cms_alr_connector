{#-
    Casts a CMS-HCC risk score or person-years fraction as numeric(38,14),
    with or without precision/scale depending on adapter type.

    CMS ships the risk scores (bene_rsk_r_scre_01-12, the four *_score columns
    and their dem_* demographic counterparts) and the person-years fractions
    (bene_psnyrs_dual in Table 1-1, bene_psnyrs and bene_psnyrs_lis_dual in
    Table 1-9) with up to 14 decimals. cast_numeric()'s numeric(38,2) is the
    right contract for the connector's counts and dollar amounts but rounds
    these columns, and the risk ratios and risk-adjusted benchmarks computed
    downstream inherit that rounding. Fourteen decimals keeps every digit CMS
    publishes, while 24 integer digits are far more than a score will ever
    need.

    BigQuery does not accept a parameterized NUMERIC in a cast. Bare NUMERIC has
    a fixed scale of 9, short of the contract, so this macro uses BIGNUMERIC
    (fixed at 76,38) there. Every other adapter honours numeric(38,14).
-#}

{%- macro cast_score(column_name) -%}

    {{ return(adapter.dispatch('cast_score')(column_name)) }}

{%- endmacro -%}

{%- macro bigquery__cast_score(column_name) -%}

    cast( {{ column_name }} as bignumeric )

{%- endmacro -%}

{%- macro default__cast_score(column_name) %}

    cast( {{ column_name }} as numeric(38,14) )

{%- endmacro -%}

{%- macro redshift__cast_score(column_name) -%}

    cast( {{ column_name }} as numeric(38,14) )

{%- endmacro -%}

{%- macro snowflake__cast_score(column_name) %}

    cast( {{ column_name }} as numeric(38,14) )

{%- endmacro -%}
