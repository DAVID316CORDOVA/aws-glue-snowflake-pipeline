{% snapshot player_status_snapshot %}

{{
  config(
    target_schema='silver',
    unique_key='player_id',
    strategy='timestamp',
    updated_at='_loaded_at'
  )
}}

select
    player_id,
    alias,
    regulatory_status,
    verified,
    city,
    _loaded_at
from {{ ref('stg_player_data') }}

{% endsnapshot %}
