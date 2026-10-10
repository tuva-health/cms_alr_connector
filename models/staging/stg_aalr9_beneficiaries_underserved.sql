SELECT
  cast(bene_mbi_id as {{ dbt.type_string() }} ) as bene_mbi_id,
	cast(adi_natrank as integer) as adi_natrank ,
	cast(bene_lis_status as integer) as bene_lis_status ,
	cast(bene_dual_status as integer) as bene_dual_status ,
	{{ cast_score('bene_psnyrs_lis_dual') }} as bene_psnyrs_lis_dual ,
	{{ cast_score('bene_psnyrs') }} as bene_psnyrs ,
	cast(directory_name as {{ dbt.type_string() }} ) as directory_name,
	cast(file_name as {{ dbt.type_string() }} ) as file_name,
	{{ extract_file_metadata() }}
FROM {{ source('cms_ssp_reports', 'aalr9_beneficiaries_underserved')}}