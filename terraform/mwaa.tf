## =================================================================
## mwaa.tf
## Amazon MWAA environment. Runs in a dedicated VPC (mwaa_network.tf)
## instead of the shared VPCDatalake VPC.
## =================================================================

resource "aws_security_group" "mwaa" {
  name        = "mwaa-sg"
  description = "Security Group for MWAA Airflow environment"
  vpc_id      = aws_vpc.mwaa_prod.id

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
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "arn:aws:sns:us-east-1:211125514336:player-pipeline-alerts"
      }
    ]
  })
}

resource "aws_mwaa_environment" "player_pipeline" {
  name               = "player-data-pipeline-mwaa"
  airflow_version    = "2.10.3"
  environment_class  = "mw1.small"
  execution_role_arn = aws_iam_role.mwaa_execution.arn

  source_bucket_arn = aws_s3_bucket.mwaa_dags.arn
  dag_s3_path       = "dags"

  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids = [
      aws_subnet.mwaa_prod_a.id,
      aws_subnet.mwaa_prod_b.id
    ]
  }

  webserver_access_mode = "PUBLIC_ONLY"

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