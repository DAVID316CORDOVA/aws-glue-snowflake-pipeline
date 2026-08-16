-- Custom singular test: fails if any underage player leaked into
-- dim_players despite the WHERE flag_menor_de_edad = false filter.
-- A non-empty result here means that filter silently broke.
select p.player_id
from {{ ref('dim_players') }} p
inner join {{ ref('stg_player_data') }} s
    on p.player_id = s.player_id
where s.flag_menor_de_edad = true
