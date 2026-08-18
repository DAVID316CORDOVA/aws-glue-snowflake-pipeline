
    
    

with all_values as (

    select
        national_id_type_code as value_field,
        count(*) as n_records

    from PLAYER_ANALYTICS.silver.stg_player_data
    group by national_id_type_code

)

select *
from all_values
where value_field not in (
    '1','2','3'
)


