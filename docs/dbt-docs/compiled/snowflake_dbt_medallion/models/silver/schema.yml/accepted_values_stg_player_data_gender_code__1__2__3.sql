
    
    

with all_values as (

    select
        gender_code as value_field,
        count(*) as n_records

    from PLAYER_ANALYTICS.silver.stg_player_data
    group by gender_code

)

select *
from all_values
where value_field not in (
    '1','2','3'
)


