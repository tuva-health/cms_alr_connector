/*
    One row per person and month, from the ALR that governs the month
    (aalr_history_filtered), in the_tuva_project's provider_attribution input
    format (TUVA-121).

    person_id is the beneficiary's current MBI: the ALR MBI mapped through the
    CCLF9 crosswalk (medicare_cclf_connector's int_beneficiary_xref_deduped),
    with the same join medicare_cclf_connector uses for ALR enrollment in
    int_eligibility_member_months_combined:
    coalesce(xref.crnt_num, mbi), left join on prvs_num. Attribution then sits
    under the same person as eligibility, so it joins core.member_month after
    an MBI change.

    If the governing rows list both a previous and the current MBI for the
    same month, the crosswalk maps them to one person-month; keep one row,
    ranked the way the governing file is chosen (earliest performance year,
    lowest priority, later T-stamp), then the row already carrying the current
    MBI.
*/

with beneficiary_xref as (

    select
          prvs_num
        , crnt_num
    from {{ ref('medicare_cclf_connector', 'int_beneficiary_xref_deduped') }}

)

, attribution as (

    select
          coalesce(beneficiary_xref.crnt_num, ahf.bene_mbi_id) as person_id
        , ahf.bene_mbi_id
        , ahf.enroll_month
        , ahf.top_npi
        , ahf.top_tin
        , ahf.file_name
        , ahf.period_end_date
        , row_number() over (
            partition by
                  coalesce(beneficiary_xref.crnt_num, ahf.bene_mbi_id)
                , ahf.enroll_month
            order by
                  ahf.performance_year
                , ahf.priority
                , ahf.iteration desc
                , case when beneficiary_xref.crnt_num is null then 0 else 1 end
                , ahf.bene_mbi_id
          ) as person_month_rank
    from {{ ref('aalr_history_filtered') }} as ahf
    left join beneficiary_xref
        on ahf.bene_mbi_id = beneficiary_xref.prvs_num
    where ahf.enroll_flag > 0

)

SELECT
    cast(person_id as {{ dbt.type_string() }}) as person_id
  , cast(person_id as {{ dbt.type_string() }}) as member_id
  , cast(person_id as {{ dbt.type_string() }}) as patient_id
  , cast({{ format_yyyymm('enroll_month') }} as {{ dbt.type_string() }}) as year_month
  , cast('medicare' as {{ dbt.type_string() }}) as payer
  , cast('medicare' as {{ dbt.type_string() }}) as {{ quote_column('plan') }}
  , cast('medicare' as {{ dbt.type_string() }}) as data_source
  , cast(top_npi as {{ dbt.type_string() }}) as payer_attributed_provider
  , cast(top_tin as {{ dbt.type_string() }}) as payer_attributed_provider_practice
  , cast(null as {{ dbt.type_string() }}) as payer_attributed_provider_organization
  , cast(null as {{ dbt.type_string() }}) as payer_attributed_provider_lob
  , cast(null as {{ dbt.type_string() }}) as custom_attributed_provider
  , cast(null as {{ dbt.type_string() }}) as custom_attributed_provider_practice
  , cast(null as {{ dbt.type_string() }}) as custom_attributed_provider_organization
  , cast(null as {{ dbt.type_string() }}) as custom_attributed_provider_lob
  -- Tuva Core 1.0 provider_attribution contract columns. The governing ALR's
  -- Table 1-1 file, and its period end as the load date, the same value
  -- `enrollment` publishes as file_date (medicare_cclf_connector's ingest_datetime).
  , cast(file_name as {{ dbt.type_string() }}) as file_name
  , cast(period_end_date as {{ dbt.type_timestamp() }}) as ingest_datetime
  , cast(null as {{ dbt.type_string() }}) as tuva_last_run
FROM attribution
WHERE person_month_rank = 1
