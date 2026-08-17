"""
Lambda subscribed to the pipeline-alerts SNS topic.

Reads the Slack incoming webhook URL from Secrets Manager at runtime
(never hardcoded, never passed as a Lambda environment variable) and
posts a formatted message to the pipeline-alerts Slack channel.
"""

import json
import os
import urllib.request

import boto3

secrets_client = boto3.client("secretsmanager")


def get_webhook_url() -> str:
    secret_name = os.environ["SLACK_WEBHOOK_SECRET_NAME"]
    response = secrets_client.get_secret_value(SecretId=secret_name)
    secret = json.loads(response["SecretString"])
    return secret["webhook_url"]


def lambda_handler(event, context):
    webhook_url = get_webhook_url()

    for record in event["Records"]:
        sns_message = record["Sns"]["Message"]

        slack_payload = {
            "text": f":rotating_light: *Pipeline Alert*\n{sns_message}"
        }

        request = urllib.request.Request(
            webhook_url,
            data=json.dumps(slack_payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(request)

    return {"statusCode": 200}