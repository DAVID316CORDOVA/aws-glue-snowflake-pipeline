

-- Bronze layer: technical type casting only. The CASE WHEN business-rule
-- mappings that used to live in the Glue/PySpark job (national_id_type,
-- currency, gender, status codes) are NOT applied here on purpose --
-- they now live in Silver as testable SQL instead of Spark code.
select
    db,
    id,
    alias,
    type,
    regulatory_status,
    first_name,
    last_name,
    middle_name,
    try_cast(birth_date as date)       as birth_date,
    gender,
    email,
    phone,
    address,
    city,
    state,
    province,
    try_cast(created_date as timestamp) as created_date,
    source_tag,
    currency,
    try_cast(verified as boolean)       as verified,
    national_id,
    nationality,
    external_id,
    national_id_type,
    _file_name,
    _loaded_at
from PLAYER_ANALYTICS.RAW.player_data