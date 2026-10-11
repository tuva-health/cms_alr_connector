SELECT
    cast(bene_mbi_id as {{ dbt.type_string() }}) as person_id
  , cast(bene_mbi_id as {{ dbt.type_string() }}) as member_id
  , cast(bene_mbi_id as {{ dbt.type_string() }}) as patient_id
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
FROM {{ ref('aalr_history_filtered') }}
WHERE enroll_flag > 0
