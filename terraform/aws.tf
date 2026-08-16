## =================================================================
## aws.tf
## AWS infrastructure for the practice Glue job: a NEW job, separate
## from the real func_player_delta_PE, that only extracts (SELECT)
## from MySQL and writes raw CSV to S3 -- no business-rule transforms.
## Also provisions the S3 -> SQS event notification, preserving the
## bucket's existing Lambda notification so it is never overwritten.
## =================================================================

## -----------------------------------------------------------------
## EXISTING BUCKET (data source, not managed/created by Terraform)
## -----------------------------------------------------------------

## This data source references the existing shared bucket without
## trying to create or fully own it. It is production infrastructure
## used by other pipelines, so Terraform only reads from it here.
data "aws_s3_bucket" "dlk_olimpo" {
  bucket = "dlk-olimpo"
}


## -----------------------------------------------------------------
## SQS QUEUE
## -----------------------------------------------------------------

## This resource creates the queue that receives a notification every
## time a new CSV lands under the practice prefix. Snowpipe (or a
## Lambda consumer, in a later step) reads from this queue.
resource "aws_sqs_queue" "player_csv_notifications" {
  ## This line sets the queue name.
  name = "dwh-player-csv-notifications"

  ## This line keeps messages available for 4 days before they expire,
  ## giving enough buffer time even if the downstream consumer is
  ## delayed or temporarily down.
  message_retention_seconds = 345600
}

## This resource grants S3 permission to publish messages to the
## queue above. S3 cannot write to an SQS queue without this explicit
## policy -- by default, cross-service publishing is denied.
resource "aws_sqs_queue_policy" "allow_s3_to_send" {
  ## This line attaches the policy to the queue created above.
  queue_url = aws_sqs_queue.player_csv_notifications.id

  ## This line defines the actual permission: allow the S3 service
  ## principal to call SendMessage on this queue, but ONLY when the
  ## request originates from this specific bucket (the Condition
  ## block), preventing any other S3 bucket from writing here.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.player_csv_notifications.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = data.aws_s3_bucket.dlk_olimpo.arn
        }
      }
    }]
  })
}


## -----------------------------------------------------------------
## S3 EVENT NOTIFICATION
## -----------------------------------------------------------------

## This resource configures the bucket's event notifications. It
## MUST declare every notification rule the bucket has -- Terraform
## treats this as the full desired state, so any rule left out here
## gets deleted. The existing Lambda notification (used by an
## unrelated pipeline) is declared below purely so Terraform knows
## to keep it, not create or modify it.
resource "aws_s3_bucket_notification" "dlk_olimpo_notifications" {
  bucket = data.aws_s3_bucket.dlk_olimpo.id

  ## This block re-declares the PRE-EXISTING Lambda notification for
  ## the WhatsApp channel image optimizer, so applying this resource
  ## does not remove it.
  lambda_function {
    id                  = "optimize-canal-difusion-documents"
    lambda_function_arn = "arn:aws:lambda:us-east-1:211125514336:function:olimpo-wa-channel-image-optimizer-dev"
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "canal-difusion/documents/"
  }




  # This block notifies Snowflake's own SQS queue directly, which is
  ## what AUTO_INGEST=TRUE Snowpipe actually listens to -- Snowflake
  ## manages this queue internally, we just need S3 to notify it.
  queue {
    id            = "snowflake-player-data-pipe"
    queue_arn     = "arn:aws:sqs:us-east-1:781425929845:sf-snowpipe-AIDA3L4E5NZ26MMCY7KIX-3bRqekCtw-ey-lr8VA-cYA"
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/PE/DWH/dwh_player_csv/"
    filter_suffix = ".csv"
  }



  ## This line ensures the queue policy above is applied before this
  ## notification tries to use it -- otherwise S3 would attempt to
  ## validate permissions on a queue that doesn't have them yet.
  depends_on = [aws_sqs_queue_policy.allow_s3_to_send]
}


## -----------------------------------------------------------------
## GLUE JOB (extract-only, no business logic -- raw layer feeder)
## -----------------------------------------------------------------

## This resource creates a NEW, separate Glue job -- it does not
## touch or modify the real func_player_delta_PE job. It reuses the
## existing IAM role and VPC connections (read-only access to the
## same Aurora database), but its script only SELECTs and writes raw
## CSV -- the CASE WHEN business-rule mappings that used to live here
## now live in dbt/Silver instead.
resource "aws_glue_job" "player_raw" {
  name     = "func_player_raw"
  role_arn = "arn:aws:iam::211125514336:role/Role_Glue_Acces"

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  max_retries       = 0
  timeout           = 60
  execution_class   = "STANDARD"

  command {
    name            = "glueetl"
    script_location = "s3://aws-glue-assets-211125514336-us-east-1/scripts/func_player_raw.py"
    python_version  = "3"
  }

  connections = ["InternetConnection", "Aurora connection"]

  default_arguments = {
    "--job-language" = "python"
  }
}



## -----------------------------------------------------------------
## IAM ROLE: allows the Snowflake storage integration to read S3
## -----------------------------------------------------------------

## This resource creates the real IAM role that Snowflake assumes to
## read files from the bucket. The trust policy below only allows
## Snowflake's specific IAM user to assume this role, AND only when
## it presents the exact external ID Snowflake generated -- this
## external-id check is what prevents a different Snowflake account
## (or anyone else who somehow learned this ARN) from assuming the
## role, since the external ID is a shared secret only this specific
## storage integration knows.
resource "aws_iam_role" "snowflake_s3_player_data" {
  name = "snowflake-s3-player-data-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::781425929845:user/vxl32000-s"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "BIC01670_SFCRole=4_pHyocW6F8c9BO3GbJ24HJZ3Alcg="
        }
      }
    }]
  })

  description = "Allows Snowflake's storage integration to read dwh_player_csv/ from S3. Trust is scoped to Snowflake's specific IAM user and external ID."
}

## This resource grants the role above just enough permission to read
## objects from the specific prefix this project uses -- not the
## whole bucket, following least-privilege.
resource "aws_iam_role_policy" "snowflake_s3_read" {
  name = "snowflake-s3-read-player-data"
  role = aws_iam_role.snowflake_s3_player_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "arn:aws:s3:::dlk-olimpo/raw/PE/DWH/dwh_player_csv/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::dlk-olimpo"
        Condition = {
          StringLike = {
            "s3:prefix" = ["raw/PE/DWH/dwh_player_csv/*"]
          }
        }
      }
    ]
  })
}
