{{ config(tags=['fixture']) }}

-- Depend on both final models so this test runs after them: a failing
-- fixture test then never skips enrollment or provider_attribution.
-- depends_on: {{ ref('enrollment') }}
-- depends_on: {{ ref('provider_attribution') }}

/*
    Fixture scenario A14 (TUVA-134): an assigned disabled and an assigned
    aged/dual beneficiary, listed in every ALR delivery for the whole fixture
    window with a single EnrollFlag code, so the performance year 2025
    quarterly ALRs carry their type's risk score column.

    9TT0FK2XX12  disabled (2): enrolled 2023-10..2026-03, flag 2 every month.
    9TT0FK2XX13  aged/dual (3): enrolled 2023-10..2026-03, flag 3 every month.

    2025-01..09 is governed by the 2025Q3 redelivery (T0310000), whose rows
    carry only the type's score column: dis_score 0.55247300000000 (XX12),
    agdu_score 0.56039200000000 (XX13); the superseded T0300000 has other
    values. 2025-10..2026-03 comes from 2026Q1 with the same column filled.
    2024 rows (AALR.Y2024) carry the monthly bene_rsk_r_scre_* instead.
*/

with flags as (

    select
          bene_mbi_id
        , enroll_month
        , enroll_flag
    from {{ ref('aalr_history_filtered') }}
    where bene_mbi_id in ('9TT0FK2XX12', '9TT0FK2XX13')
      and enroll_flag > 0

)

, a14_rows as (

    select
          current_bene_mbi_id as bene_mbi_id
        , cast(enrollment_start_date as date) as enroll_month
        , file_name
        , esrd_score
        , dis_score
        , agdu_score
        , agnd_score
        , bene_rsk_r_scre_01
    from {{ ref('enrollment') }}
    where current_bene_mbi_id in ('9TT0FK2XX12', '9TT0FK2XX13')

)

, type_column as (

    -- the score in the beneficiary's type column, and whether any other type column is filled
    select
          bene_mbi_id
        , enroll_month
        , file_name
        , bene_rsk_r_scre_01
        , case when bene_mbi_id = '9TT0FK2XX12' then dis_score else agdu_score end as type_score
        , case
            when esrd_score is not null or agnd_score is not null then 1
            when bene_mbi_id = '9TT0FK2XX12' and agdu_score is not null then 1
            when bene_mbi_id = '9TT0FK2XX13' and dis_score is not null then 1
            else 0
          end as other_type_filled
    from a14_rows

)

{{ fixture_enrollment_months_diff('A14', '9TT0FK2XX12', [('2023-10-01', '2026-03-01')]) }}
union all
{{ fixture_enrollment_months_diff('A14', '9TT0FK2XX13', [('2023-10-01', '2026-03-01')]) }}
union all
select
      'A14' as scenario
    , bene_mbi_id
    , enroll_month
    , 'unexpected EnrollFlag ' || cast(enroll_flag as {{ dbt.type_string() }}) as failure
from flags
where (bene_mbi_id = '9TT0FK2XX12' and enroll_flag <> 2)
   or (bene_mbi_id = '9TT0FK2XX13' and enroll_flag <> 3)
union all
select
      'A14' as scenario
    , bene_mbi_id
    , enroll_month
    , 'not governed by the 2025Q3 redelivery: ' || coalesce(file_name, 'null') as failure
from type_column
where enroll_month between cast('2025-01-01' as date) and cast('2025-09-01' as date)
  -- '!' escapes '_': Snowflake treats '\' in a string literal as an escape, so escape '\' never terminates.
  and (file_name is null or file_name not like '%.QALR.2025Q3.D259999.T0310000!_1-1.csv' escape '!')
union all
select
      'A14' as scenario
    , bene_mbi_id
    , enroll_month
    , 'wrong 2025Q3 score in the type column, or another type column filled' as failure
from type_column
where enroll_month between cast('2025-01-01' as date) and cast('2025-09-01' as date)
  and (other_type_filled = 1
       or type_score is null
       or type_score <> case
                           when bene_mbi_id = '9TT0FK2XX12' then cast('0.55247300000000' as decimal(38, 14))
                           else cast('0.56039200000000' as decimal(38, 14))
                         end)
union all
select
      'A14' as scenario
    , bene_mbi_id
    , enroll_month
    , '2026Q1 row without the type score column alone' as failure
from type_column
where enroll_month >= cast('2025-10-01' as date)
  and (other_type_filled = 1 or type_score is null)
union all
select
      'A14' as scenario
    , bene_mbi_id
    , enroll_month
    , 'AALR.Y2024 row without bene_rsk_r_scre_01, or with a type score' as failure
from type_column
where enroll_month between cast('2024-01-01' as date) and cast('2024-12-01' as date)
  and (bene_rsk_r_scre_01 is null or type_score is not null or other_type_filled = 1)
