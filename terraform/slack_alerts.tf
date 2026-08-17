# -----------------------------------------------------------------
# Slack alerting: SNS -> Lambda -> Slack incoming webhook.
# SNS cannot deliver to Slack natively, so a small Lambda subscribes
# to the topic, reformats the message, and posts it to the webhook.
# -----------------------------------------------------------------

# The webhook URL itself is NOT managed by Terraform (it's a secret).
# The secret container is created here, but its value is set manually
# via `aws secretsmanager put-secret-value` (or create-secret) outside
# of Terraform/git, so it never ends up in the .tfstate in plain text
# nor in version control.
resource "aws_secretsmanager_secret" "slack_webhook" {
  name        = "pipeline-alerts/slack-webhook"
  description = "Slack incoming webhook URL for pipeline failure alerts (value set manually, not via Terraform)"
}

# IAM role assumed by the alerting Lambda.
resource "aws_iam_role" "slack_alert_lambda" {
  name = "pipeline-alert-slack-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Minimal permissions: write its own logs, and read the one secret it needs.
resource "aws_iam_role_policy" "slack_alert_lambda_policy" {
  name = "slack-alert-lambda-policy"
  role = aws_iam_role.slack_alert_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.slack_webhook.arn
      }
    ]
  })
}

# The Lambda function itself. Code lives in lambda/slack_alert/handler.py,
# zipped at plan/apply time by the archive_file data source below.
data "archive_file" "slack_alert_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/slack_alert/handler.py"
  output_path = "${path.module}/../lambda/slack_alert/handler.zip"
}

resource "aws_lambda_function" "slack_alert" {
  function_name    = "pipeline-alert-to-slack"
  role             = aws_iam_role.slack_alert_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.slack_alert_lambda_zip.output_path
  source_code_hash = data.archive_file.slack_alert_lambda_zip.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_SECRET_NAME = aws_secretsmanager_secret.slack_webhook.name
    }
  }
}

# Allow SNS to invoke this Lambda.
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.pipeline_alerts.arn
}

# Subscribe the Lambda to the same topic used for email alerts.
resource "aws_sns_topic_subscription" "pipeline_alerts_slack" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_alert.arn
}