
    
    

select
    player_id as unique_field,
    count(*) as n_records

from PLAYER_ANALYTICS.silver.stg_player_data
where player_id is not null
group by player_id
having count(*) > 1


