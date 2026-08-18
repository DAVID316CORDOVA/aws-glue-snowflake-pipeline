

-- Incremental version of the player extraction: on first run, processes
-- all of bronze_player_data; on later runs, only rows loaded after the
-- last _loaded_at already in this table -- avoiding a full reprocess
-- every time a new Glue-generated CSV lands via Snowpipe.
select
    db,
    id as player_id,
    alias,
    type,
    regulatory_status,
    first_name,
    last_name,
    middle_name,
    birth_date,
    gender,
    email,
    phone,
    address,
    city,
    state,
    province,
    created_date,
    source_tag,
    currency,
    verified,
    national_id,
    nationality,
    external_id,
    national_id_type,
    _file_name,
    _loaded_at
from PLAYER_ANALYTICS.bronze.bronze_player_data


where _loaded_at > (select coalesce(max(_loaded_at), '1900-01-01') from PLAYER_ANALYTICS.silver.player_data_incremental)


qualify row_number() over (
    partition by id
    order by _loaded_at desc
) = 1