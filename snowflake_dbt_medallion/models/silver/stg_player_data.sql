{{
  config(
    materialized='view'
  )
}}

with source as (
    select * from {{ ref('bronze_player_data') }}
),
deduplicado as (
    select *,
        row_number() over (
            partition by id
            order by _loaded_at desc
        ) as rn_id
    from source
    qualify rn_id = 1
),
mapeado as (
    select
        id as player_id,
        db,
        alias,
        type,
        regulatory_status,

        case
            when national_id_type = 'PASAPORTE'  then 1
            when national_id_type = 'EXTRANJERIA' then 2
            when national_id_type = 'DNI'         then 3
            else 1
        end as national_id_type_code,

        case
            when currency = 'USD' then 4
            when currency = 'PEN' then 14
            else 14
        end as currency_code,

        case
            when regulatory_status = 'ABIERTO'    and verified = true  then 2
            when regulatory_status = 'ABIERTO'    and verified = false then 5
            when regulatory_status = 'SUSPENDIDO' then 7
            when regulatory_status = 'BLOQUEADO'  then 4
            when regulatory_status = 'NO_ACTIVADO' then 1
            when regulatory_status = 'CERRADO'    then 3
            else 1
        end as status_code,

        case
            when gender = 'MALE'      then 1
            when gender = 'FEMALE'    then 2
            when gender = 'UNDEFINED' then 3
            else 3
        end as gender_code,

        first_name,
        last_name,
        middle_name,
        birth_date,
        trim(lower(email)) as email,
        phone,
        address,
        city,
        state,
        province,
        created_date,
        source_tag,
        verified,
        national_id,
        nationality,
        external_id,
        _file_name,
        _loaded_at,

        -- Age at time of registration, in years. Used below to flag
        -- underage accounts -- a compliance-relevant condition that
        -- must stay visible and auditable, never silently dropped.
        datediff(year, birth_date, created_date) as edad_al_registro,

        case when email is null or email not like '%@%' then true else false end as flag_email_invalido,
        case when created_date > current_timestamp() then true else false end as flag_fecha_futura,

        -- Compliance flag: player under 18 at the time of registration.
        -- Kept as a flag, not a filter -- these rows must remain visible
        -- for compliance review, not silently dropped from the pipeline.
        case
            when birth_date is null then null  -- can't evaluate age, flagged separately below
            when datediff(year, birth_date, created_date) < 18 then true
            else false
        end as flag_menor_de_edad,

        -- Compliance flag: no national ID on file. Same principle --
        -- this needs to be reviewable, not deleted.
        case
            when national_id is null or trim(national_id) = '' then true
            else false
        end as flag_sin_documento_identidad

    from deduplicado
)
select * from mapeado
