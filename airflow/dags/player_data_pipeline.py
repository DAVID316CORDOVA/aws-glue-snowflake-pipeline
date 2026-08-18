"""
DAG: player_data_pipeline

Orchestrates the full pipeline: trigger the Glue extract job, wait
(actively, not on a fixed timer) for the resulting CSV to be
auto-ingested into Snowflake RAW via Snowpipe, then run dbt.

Uses Sensors instead of a fixed sleep -- this avoids the "hardcoded
24h time window" anti-pattern: the DAG waits exactly as long as
Snowpipe actually takes, confirmed by querying Snowflake directly,
not by guessing a duration.

Failure alerting: any task failure (after retries are exhausted)
publishes to the pipeline-alerts SNS topic, which fans out to email
and Slack. See notify_failure() below.
"""

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.amazon.aws.hooks.base_aws import AwsBaseHook
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.sensors.glue import GlueJobSensor
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
from airflow.sensors.sql import SqlSensor

DBT_PROJECT_DIR = "/opt/airflow/dbt_project"
SNOWFLAKE_CONN_ID = "snowflake_default"
AWS_CONN_ID = "aws_default"

# ARN of the SNS topic created by terraform/sns.tf. Fans out to email
# and Slack (via a Lambda subscriber) so this DAG never has to know
# where alerts actually end up -- adding a new channel later (e.g.
# PagerDuty) means adding a subscription to the topic, not touching
# this file.
# TODO: move to an Airflow Variable instead of hardcoding, now that
# the real topic ARN is known post-apply.
SNS_TOPIC_ARN = "arn:aws:sns:us-east-1:211125514336:player-pipeline-alerts"


def notify_failure(context: dict) -> None:
    """
    DAG-level on_failure_callback: fires whenever any task in this
    DAG fails, after Airflow's own retries (see default_args) are
    exhausted. Publishing here -- once, at the DAG level -- avoids
    repeating the same callback across all 6 tasks.

    Uses boto3 directly (not SnsPublishOperator) because this runs
    inside a callback, not as a scheduled task in the DAG graph.
    Credentials come from the same aws_default connection Airflow
    already uses elsewhere in this DAG -- no extra setup needed.
    """
    task_instance = context["task_instance"]

    message = (
        f"Airflow task failed\n\n"
        f"DAG: {context['dag'].dag_id}\n"
        f"Task: {task_instance.task_id}\n"
        f"Execution date: {context['execution_date']}\n"
        f"Error: {context.get('exception')}\n"
        f"Logs: {task_instance.log_url}"
    )

    # Uses the aws_default Airflow connection (same one Glue/Snowpipe
    # tasks already rely on) instead of a raw boto3 client, which has
    # no credentials inside the Airflow container unless explicitly
    # passed a connection to read from.
    sns_client = AwsBaseHook(aws_conn_id=AWS_CONN_ID, client_type="sns").get_conn()
    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[Pipeline Alert] {context['dag'].dag_id} - {task_instance.task_id} failed",
        Message=message,
    )


default_args = {
    "owner": "david",
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
    "on_failure_callback": notify_failure,
}

with DAG(
    dag_id="player_data_pipeline",
    default_args=default_args,
    description="Glue extract -> S3 -> Snowpipe -> dbt, waiting on real Snowpipe completion",
    schedule_interval="@daily",
    start_date=datetime(2026, 8, 1),
    catchup=False,
    tags=["glue", "snowpipe", "dbt", "player-data"],
) as dag:

    # ── STEP 1: trigger the Glue extract job ──────────────────────────────
    trigger_glue = GlueJobOperator(
        task_id="trigger_glue_extract",
        job_name="func_player_raw",
        aws_conn_id=AWS_CONN_ID,
        region_name="us-east-1",
        wait_for_completion=False,  # don't block here -- the sensor below does that
    )

    # ── STEP 2: wait for the Glue job run itself to finish ────────────────
    wait_for_glue = GlueJobSensor(
        task_id="wait_for_glue_completion",
        job_name="func_player_raw",
        run_id="{{ task_instance.xcom_pull(task_ids='trigger_glue_extract') }}",
        aws_conn_id=AWS_CONN_ID,
        poke_interval=15,
        timeout=60 * 10,  # give up after 10 minutes -- longer than this job should ever take
    )

    # ── STEP 3: wait for Snowpipe to actually load the new file ───────────
    # This is the piece that answers "how does Airflow know when
    # Snowpipe is done?" -- it doesn't guess. It repeatedly queries
    # Snowflake, checking whether a row loaded in the last few minutes
    # exists, and only proceeds once that's true (or times out).
    wait_for_snowpipe = SqlSensor(
        task_id="wait_for_snowpipe_load",
        conn_id=SNOWFLAKE_CONN_ID,
        sql="""
            select count(*)
            from PLAYER_ANALYTICS.RAW.player_data
            where _loaded_at > dateadd('minute', -10, current_timestamp())
        """,
        poke_interval=15,
        timeout=60 * 10,
        mode="poke",
    )

    # ── STEP 4-6: dbt run / test / snapshot ────────────────────────────────
    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt run",

    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt test",
    )

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt snapshot",
    )

    trigger_glue >> wait_for_glue >> wait_for_snowpipe >> dbt_run >> dbt_test >> dbt_snapshot