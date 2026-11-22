{#-
    Columns parsed from an ALR FILE_NAME
    (P.A<ACO>.ACO.<QALR|AALR>.[<period>.]D<YY>9999.T<nnnnnnn>_1-<table>.csv).

    ALR_FILE_TYPE classifies the delivery with mssp_file_parameters.file_type's
    values, plus the settlement AALR (TUVA-152):
      quarterly   QALR
      initial     AALR with no period token (HASSGN initial assignment)
      benchmark   AALR whose Y<yyyy> period is earlier than its performance
                  year (BNMRK bundle: PY2025 ships Y2022..Y2024)
      settlement  AALR whose Y<yyyy> period is its own performance year (STLMT
                  bundle: AALR.Y2025.D259999 for PY2025)
    Anything else is NULL. A settlement AALR parses to the same PERFORMANCE_YEAR
    and FILE_PERIOD as that year's initial assignment, and CMS can ship both
    under one T-stamp, so only ALR_FILE_TYPE and DELIVERY_ID tell them apart.

    DELIVERY_ID is FILE_NAME without its _1-<table>.csv suffix, the same for
    every table of one delivery: join one ALR table to another on it.
-#}
{% macro extract_file_metadata() %}
split_part(FILE_NAME, '.', 4) as FILE_TYPE,
    CASE WHEN split_part(FILE_NAME, '.', 5) LIKE 'D%'
        THEN concat('Y20', substring(split_part(FILE_NAME, '.', 5),2,2))
        ELSE split_part(FILE_NAME, '.', 5)
        END AS FILE_PERIOD,
    CASE WHEN split_part(FILE_NAME, '.', 5) LIKE 'D%'
      THEN concat('20', substring(split_part(FILE_NAME, '.', 5),2,2))
      ELSE concat('20', substring(split_part(FILE_NAME, '.', 6),2,2)) END as PERFORMANCE_YEAR,
    CASE WHEN split_part(FILE_NAME, '.', 5) LIKE 'D%'
          THEN split_part(FILE_NAME, '.', 6)
          ELSE split_part(FILE_NAME, '.', 7) END as ITERATION,
    CASE
        WHEN split_part(FILE_NAME, '.', 4) = 'QALR' THEN 'quarterly'
        WHEN split_part(FILE_NAME, '.', 4) <> 'AALR' THEN NULL
        WHEN split_part(FILE_NAME, '.', 5) LIKE 'D%' THEN 'initial'
        WHEN split_part(FILE_NAME, '.', 5) NOT LIKE 'Y%' THEN NULL
        WHEN substring(split_part(FILE_NAME, '.', 5),2,4) = concat('20', substring(split_part(FILE_NAME, '.', 6),2,2))
          THEN 'settlement'
        ELSE 'benchmark'
        END AS ALR_FILE_TYPE,
    split_part(FILE_NAME, '_', 1) AS DELIVERY_ID
{% endmacro %}
