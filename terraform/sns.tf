
# Current AWS account identity, used to scope the SNS topic policy
# to this account only (avoids hardcoding the account ID).
data "aws_caller_identity" "current" {}


# SNS topic that receives failure notifications from the Airflow DAG
# (published via boto3 in the on_failure_callback) and fans them out
# to email + Slack (Slack delivery handled by a Lambda subscriber).
resource "aws_sns_topic" "pipeline_alerts" {
  name = "player-pipeline-alerts"
}

# Email subscription — delivers failure alerts directly to an inbox.
# NOTE: AWS sends a confirmation email after apply; the subscription
# stays PendingConfirmation until that link is clicked manually.
resource "aws_sns_topic_subscription" "pipeline_alerts_email" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Policy allowing the MWAA/Airflow execution role to publish to this topic.
resource "aws_sns_topic_policy" "pipeline_alerts_policy" {
  arn = aws_sns_topic.pipeline_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountPublish"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.pipeline_alerts.arn
      }
    ]
  })
}