"""
func_player_raw.py

AWS Glue job: extracts raw player data from MySQL/Aurora and writes it
as a timestamped CSV to S3, ready for Snowpipe to pick up.

This job is intentionally EXTRACT-ONLY. Unlike the original
func_player_delta_PE job, it does NOT apply business-rule transforms
(the CASE WHEN mappings for national_id_type, currency, gender, status).
Those now live in dbt/Silver instead, so they run on Snowflake's
auto-suspending warehouse rather than on this Spark cluster -- this is
the core of the cost-reduction argument for moving to Snowflake.

Credentials are read from AWS Secrets Manager (prod/emr/mysql-etl),
never hardcoded or passed as plaintext job arguments.
"""

import sys
import json
import boto3
from datetime import datetime, timedelta
from pyspark.sql import SparkSession
from awsglue.utils import getResolvedOptions


# ── CONFIG ──────────────────────────────────────────────────────────────────
SECRET_NAME = "prod/emr/mysql-etl"
AWS_REGION = "us-east-1"
S3_OUTPUT_PATH = "s3://dlk-olimpo/raw/PE/DWH/dwh_player_csv/"


def get_db_credentials():
    """Reads MySQL credentials from Secrets Manager -- never hardcoded,
    never passed as a plaintext Glue job argument."""
    client = boto3.client("secretsmanager", region_name=AWS_REGION)
    secret = client.get_secret_value(SecretId=SECRET_NAME)
    return json.loads(secret["SecretString"])


def main():
    # This job takes no custom arguments beyond the standard Glue ones --
    # credentials come from Secrets Manager, not from --useretl/--passwordetl
    # like the original job did.
    args = getResolvedOptions(sys.argv, ["JOB_NAME"])

    creds = get_db_credentials()
    db_user = creds["useretl"]
    db_password = creds["passwordetl"]
    db_host = creds["hostetl"]
    db_port = creds.get("port", "3306")

    jdbc_url = f"jdbc:mysql://{db_host}:{db_port}/data?user={db_user}&password={db_password}"

    spark = SparkSession.builder \
        .appName("func_player_raw") \
        .config("spark.sql.shuffle.partitions", "50") \
        .getOrCreate()

    # Extraction window: last 24 hours, same delta-load pattern as the
    # original job, but without the timezone/business-rule complexity --
    # this pulls a wider, simpler window since dbt will handle
    # deduplication and precise filtering downstream in Silver.
    fecha_fin = datetime.utcnow()
    fecha_inicio = fecha_fin - timedelta(hours=24)

    print(f"Extraction window: {fecha_inicio} to {fecha_fin}")

    # NOTE: no CASE WHEN mappings here on purpose. This query pulls raw
    # columns exactly as MySQL has them -- national_id_type, currency,
    # gender, status all stay as their original string values. The
    # numeric-code mapping that used to happen here now happens in
    # dbt's Silver layer instead.
    query = f"""
        SELECT
            db,
            user AS id,
            alias,
            `type`,
            regulatory_status,
            first_name,
            last_name,
            middle_name,
            birthday AS birth_date,
            gender,
            email,
            mobile AS phone,
            address,
            city,
            state,
            province,
            created_date,
            affiliate_tag AS source_tag,
            currency,
            verified,
            national_id,
            nationality,
            external_id,
            national_id_type
        FROM data.users
        WHERE company = 'OLI'
          AND created_date >= '{fecha_inicio.strftime("%Y-%m-%d %H:%M:%S")}'
          AND created_date < '{fecha_fin.strftime("%Y-%m-%d %H:%M:%S")}'
          AND currency IN ('PEN', 'USD')
    """

    df = spark.read.format("jdbc").option("url", jdbc_url).option("query", query).load()

    row_count = df.count()
    print(f"Extracted {row_count} rows.")

    if row_count == 0:
        print("No new rows in this window -- skipping CSV write.")
        return

    # Timestamped filename, so Snowpipe (or manual triggers) can pick up
    # each run as a distinct, uniquely-named file -- avoiding the
    # "same filename overwritten" issue seen in the Snowflake project's
    # Snowpipe practice.
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    output_path = f"{S3_OUTPUT_PATH}dwh_player_{timestamp}"

    # Single CSV file (coalesce(1)) since this is a small delta load --
    # for larger volumes, remove coalesce and let Spark write multiple
    # part files instead.
    df.coalesce(1).write \
        .option("header", "true") \
        .mode("overwrite") \
        .csv(output_path)

    print(f"Wrote CSV to {output_path}")


if __name__ == "__main__":
    main()