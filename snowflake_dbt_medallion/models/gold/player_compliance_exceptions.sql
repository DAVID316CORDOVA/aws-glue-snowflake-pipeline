{{
  config(
    materialized='table'
  )
}}

-- Compliance exceptions: underage players and players without a
-- national ID on file. These rows are NOT deleted anywhere upstream --
-- this table exists specifically so this information stays visible
-- and reviewable, rather than silently disappearing from the pipeline.
select
    player_id,
    alias,
    first_name,
    last_name,
    birth_date,
    edad_al_registro,
    national_id,
    national_id_type_code,
    regulatory_status,
    created_date,
    flag_menor_de_edad,
    flag_sin_documento_identidad
from {{ ref('stg_player_data') }}
where flag_menor_de_edad = true
   or flag_sin_documento_identidad = true
