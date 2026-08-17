## =================================================================
## mwaa.tf
## Amazon MWAA environment to run the Airflow DAG in a fully managed
## service, instead of only locally in Docker. Reuses existing shared
## networking (VPC, subnets, NAT Gateway) -- imported below, not
## recreated -- to avoid duplicating infrastructure.
##
## COST WARNING: aws_mwaa_environment bills continuously while it
## exists (~$0.49/hour for mw1.small), with no auto-suspend. Only
## apply this when actively testing, and destroy it right after
## (terraform destroy -target=aws_mwaa_environment.player_pipeline)
## rather than leaving it running.
## =================================================================

## -----------------------------------------------------------------
## SECURITY GROUP (already exists, imported)
## -----------------------------------------------------------------

resource "aws_security_group" "mwaa" {
  name        = "mwaa-sg"
  description = "Security Group for MWAA Airflow environment"
  vpc_id      = "vpc-0c916cec2856e4f36"

  ## Self-referencing rule: required by MWAA so its internal
  ## components (scheduler, webserver, workers) can talk to each
  ## other -- this is the standard pattern for MWAA security groups.
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


## -----------------------------------------------------------------
## S3 BUCKET FOR MWAA DAGS (already exists, imported)
## -----------------------------------------------------------------

resource "aws_s3_bucket" "mwaa_dags" {
  bucket = "dlk-mwaa-211125514336"
}

resource "aws_s3_bucket_versioning" "mwaa_dags" {
  bucket = aws_s3_bucket.mwaa_dags.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "mwaa_dags" {
  bucket                  = aws_s3_bucket.mwaa_dags.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "mwaa_execution" {
  name = "AmazonMWAA-dlk-role"

  # MWAA requires trust from BOTH services: airflow-env.amazonaws.com
  # is used during environment provisioning, while airflow.amazonaws.com
  # is used by the running Airflow service itself (task execution,
  # metric publishing). Missing either one causes CREATE_FAILED with
  # a generic INCORRECT_CONFIGURATION error and no useful logs, since
  # the failure happens before Airflow's own components ever start.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = [
          "airflow.amazonaws.com",
          "airflow-env.amazonaws.com"
        ]
      }
      Action = "sts:AssumeRole"
    }]
  })

  description = "Execution role for MWAA Airflow environment"
}





resource "aws_iam_policy" "mwaa_s3_access" {
  name = "MWAA-DLK-S3-Access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetAccountPublicAccessBlock"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mwaa_dags.arn,
          "${aws_s3_bucket.mwaa_dags.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mwaa_s3" {
  role       = aws_iam_role.mwaa_execution.name
  policy_arn = aws_iam_policy.mwaa_s3_access.arn
}

## Additional permissions MWAA needs that weren't created manually
## yet: CloudWatch Logs (to write scheduler/task logs) and permission
## to call the Glue job this pipeline triggers.
resource "aws_iam_role_policy" "mwaa_logs_and_glue" {
  name = "mwaa-logs-and-glue-access"
  role = aws_iam_role.mwaa_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:GetLogRecord",
          "logs:GetLogGroupFields",
          "logs:GetQueryResults",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:us-east-1:211125514336:log-group:airflow-*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:GetJob"
        ]
        Resource = "arn:aws:glue:us-east-1:211125514336:job/func_player_raw"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["airflow:PublishMetrics"]
        Resource = "arn:aws:airflow:us-east-1:211125514336:environment/*"
      },
      {
        # Allows the on_failure_callback in player_data_pipeline.py
        # to publish failure alerts to the pipeline-alerts SNS topic.
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "arn:aws:sns:us-east-1:211125514336:player-pipeline-alerts"
      }

    ]
  })
}


## -----------------------------------------------------------------
## MWAA ENVIRONMENT (new -- not yet created)
## -----------------------------------------------------------------

resource "aws_mwaa_environment" "player_pipeline" {
  name              = "player-data-pipeline-mwaa"
  airflow_version    = "2.10.3"
  environment_class  = "mw1.small"
  execution_role_arn = aws_iam_role.mwaa_execution.arn

  source_bucket_arn = aws_s3_bucket.mwaa_dags.arn
  dag_s3_path       = "dags"

  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids = [
      "subnet-06633febbc517c762",
      "subnet-0c9c2ac9a3b0b9b97"
    ]
  }

  # No public endpoint -- MWAA's webserver is only reachable through
  # a private network path (VPN/bastion), matching the private
  # subnets already chosen. If you need to access the UI directly
  # from your laptop, this would need to be PUBLIC_ONLY instead.
  webserver_access_mode = "PRIVATE_ONLY"

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }
    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }
    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }
}
