{#-
    CTEs top_tin and top_npi (with their ranked_tin / ranked_npi steps): each
    beneficiary's top TIN (MASTER_ID) by E&M line count in Table 1-2, and that
    TIN's top NPI by PCS count in Table 1-4, within one delivery (TUVA-108).
    Used by aalr_history and aalr_settlement_population, so both pick the
    practice and provider the same way. Emits the four CTEs comma-separated,
    without a leading or trailing comma.

    The delivery is DELIVERY_ID, the file name without its _1-<table>.csv
    suffix. Not (aco_id, performance year, file period, t_stamp): a
    settlement AALR and the initial assignment can share all four (TUVA-152).
    A plain row_number() + rn = 1, not dbt_utils.deduplicate: its default
    implementation (used on DuckDB) re-joins the ranked rows with a NATURAL
    JOIN on every column, and NULL = NULL never matches, so every row with a
    blank column (BENE_HIC_NUM, BENE_DEATH_DT) dropped out (TUVA-112).
    Ties on the count go to the lowest MASTER_ID / NPI_USED (our choice: CMS
    breaks them on the most recent primary care service date, which the ALR
    does not carry). NULLS LAST is explicit because Snowflake sorts NULLs first
    on DESC and DuckDB last.
-#}
{% macro aalr_top_tin_and_npi() %}
ranked_tin AS (
  SELECT
    tin.*,
    row_number() OVER (
      PARTITION BY tin.BENE_MBI_ID, tin.DELIVERY_ID
      ORDER BY tin.B_EM_LINE_CNT_T DESC NULLS LAST, tin.MASTER_ID ASC NULLS LAST
    ) AS rn
  FROM {{ ref('stg_aalr2_assigned_beneficiaries_tin') }} AS tin
),

-- Filter to only the top MASTER_ID (TIN) based on EM counts
top_tin AS (
  SELECT * FROM ranked_tin WHERE rn = 1
),

ranked_npi AS (
  SELECT
    npi.*,
    row_number() OVER (
      PARTITION BY npi.BENE_MBI_ID, npi.DELIVERY_ID, npi.MASTER_ID
      ORDER BY npi.PCS_COUNT DESC NULLS LAST, npi.NPI_USED ASC NULLS LAST
    ) AS rn
  FROM {{ ref('stg_aalr4_assigned_beneficiaries_tin_npi') }} AS npi
),

-- Filter to only the top NPI for each Master_ID (TIN) based on PCS counts
top_npi AS (
  SELECT * FROM ranked_npi WHERE rn = 1
)
{% endmacro %}
