## =================================================================
## providers.tf
## Two providers: AWS for Glue/S3/SQS/SNS, Snowflake for the
## database that will receive the extracted player data.
## Remote state backend: stored in S3 so both local runs and CI/CD
## read and write the same state file -- without this, GitHub Actions
## would have no memory of resources already created, and would try
## to recreate everything from scratch.
## =================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 0.95"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    bucket = "dlk-infra-211125514336"
    key    = "player-analytics/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "snowflake" {
  organization_name = "MZJLBCT"
  account_name       = "CUC08629"
  user               = "david"
  password           = var.snowflake_password
  role               = "ACCOUNTADMIN"
}
