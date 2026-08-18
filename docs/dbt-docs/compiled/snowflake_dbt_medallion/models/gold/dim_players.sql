

select
    player_id,
    db,
    alias,
    first_name,
    last_name,
    email,
    city,
    state,
    province,
    currency_code,
    national_id_type_code,
    status_code,
    gender_code,
    regulatory_status,
    verified,
    created_date,
    datediff(day, created_date, current_date()) as dias_como_jugador
from PLAYER_ANALYTICS.silver.stg_player_data
where flag_email_invalido = false
  and flag_menor_de_edad = false