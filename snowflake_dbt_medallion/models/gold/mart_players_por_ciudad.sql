{{
  config(
    materialized='table'
  )
}}

select
    city,
    currency_code,
    count(*) as total_jugadores,
    sum(case when verified then 1 else 0 end) as jugadores_verificados,
    avg(dias_como_jugador) as promedio_dias_como_jugador
from {{ ref('dim_players') }}
group by city, currency_code
order by total_jugadores desc
