
    
    

select
    player_id as unique_field,
    count(*) as n_records

from PLAYER_ANALYTICS.gold.dim_players
where player_id is not null
group by player_id
having count(*) > 1


