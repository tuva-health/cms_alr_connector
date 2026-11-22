/*
    The settlement population (TUVA-113): every beneficiary a settlement
    (STLMT) AALR lists, one row per beneficiary and settlement delivery.

    CMS's final settlement bundle for a performance year carries an AALR for
    that year (AALR.Y2025.D259999 for PY2025), with the beneficiaries CMS
    reconciled the year on and their scores and person-years. It never
    governs a month: enrollment, provider_attribution and aalr_history keep
    the quarterly, initial and benchmark ALRs (aalr_governing_file), and the
    settlement sits beside them here, so the settlement population can be
    scored on its own.

    Each row carries the delivery's Table 1-1 row as staged (EnrollFlag1..12,
    the CMS-HCC scores, HCC flags, demographics, bene_psnyrs_dual), its
    mssp_file_parameters period, the top TIN and NPI from its own Tables 1-2
    and 1-4 (aalr_top_tin_and_npi, as in aalr_history), and its own Table 1-6
    and 1-9 fields, including the person-years bene_psnyrs and
    bene_psnyrs_lis_dual. Every table is joined on delivery_id.

    CMS can deliver one settlement twice, embargoed (T0000000) and
    unembargoed (T1111111), and both copies are kept. is_latest_delivery
    marks the rows of each ACO and performance year's latest T-stamp (text
    order), which is the unembargoed copy when both exist and the only copy
    otherwise. A beneficiary listed only in an earlier copy has no
    is_latest_delivery row. A beneficiary with no Table 1-9 row in its
    delivery has NULL person-years.
*/

with settlement as (

    select
          aalr1.*
        , {{ dbt.split_part('aalr1.file_name', "'.'", 2) }} as aco_id
        , {{ dbt.split_part('aalr1.iteration', "'_'", 1) }} as t_stamp
    from {{ ref('stg_aalr1_assigned_beneficiaries') }} as aalr1
    where aalr1.alr_file_type = 'settlement'

),

{{ aalr_top_tin_and_npi() }}

select
      settlement.*
    , settlement.t_stamp = max(settlement.t_stamp) over (
        partition by settlement.aco_id, settlement.performance_year
      ) as is_latest_delivery
    , afp.report_year
    , afp.period_start_date
    , afp.period_end_date
    , tt.MASTER_ID as TOP_TIN
    , tt.B_EM_LINE_CNT_T as TIN_EM_COUNT
    , tn.NPI_USED as TOP_NPI
    , tn.PCS_COUNT as NPI_EM_COUNT
    , baov.VA_SELECTION_ONLY
    , bu.ADI_NATRANK
    , bu.BENE_LIS_STATUS
    , bu.BENE_DUAL_STATUS
    , bu.BENE_PSNYRS_LIS_DUAL
    , bu.BENE_PSNYRS
from settlement
-- aalr_file_parameters (TUVA-164): a settlement with no row keeps its rows here, with a NULL period, and the
-- alr_file_without_file_parameters test names it.
left join {{ ref('aalr_file_parameters') }} as afp
    on settlement.performance_year = afp.performance_year
   and settlement.file_period = afp.file_period
   and settlement.alr_file_type = afp.file_type
left join top_tin as tt
    on settlement.bene_mbi_id = tt.BENE_MBI_ID
   and settlement.delivery_id = tt.DELIVERY_ID
left join top_npi as tn
    on settlement.bene_mbi_id = tn.BENE_MBI_ID
   and tt.MASTER_ID = tn.MASTER_ID
   and settlement.delivery_id = tn.DELIVERY_ID
left join {{ ref('stg_aalr6_beneficiaries_assignable_or_voluntary') }} as baov
    on settlement.bene_mbi_id = baov.BENE_MBI_ID
   and settlement.delivery_id = baov.DELIVERY_ID
left join {{ ref('stg_aalr9_beneficiaries_underserved') }} as bu
    on settlement.bene_mbi_id = bu.BENE_MBI_ID
   and settlement.delivery_id = bu.DELIVERY_ID
