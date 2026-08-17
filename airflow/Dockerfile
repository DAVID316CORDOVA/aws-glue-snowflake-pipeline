FROM apache/airflow:2.10.4

USER airflow

RUN pip install --no-cache-dir dbt-core==1.12.2 dbt-snowflake==1.12.0
RUN pip install --no-cache-dir apache-airflow-providers-snowflake
RUN pip install --no-cache-dir apache-airflow-providers-amazon

# dbt-core 1.12.2 requires protobuf>=5.26 (uses the
# always_print_fields_with_no_presence parameter, added in that version).
# The base Airflow image's bundled Google provider libraries pin
# protobuf<5, which otherwise wins dependency resolution and breaks dbt.
# --no-deps forces the newer protobuf without re-resolving those unrelated
# Google libraries, which this DAG never actually uses.
RUN pip install --no-cache-dir --no-deps --force-reinstall "protobuf>=5.26,<6"
