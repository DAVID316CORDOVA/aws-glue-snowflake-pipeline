## =================================================================
## providers.tf
## Two providers: AWS for Glue/S3/SQS/SNS, Snowflake for the
## database that will receive the extracted player data.
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
