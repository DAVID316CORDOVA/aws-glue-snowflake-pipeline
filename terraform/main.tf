## =================================================================
## main.tf
## Snowflake infrastructure for the player analytics project.
## Two compute warehouses (ETL vs analytics) and two fully isolated
## databases (dev and prod), each with the medallion schema layout.
## =================================================================

## -----------------------------------------------------------------
## WAREHOUSES
## -----------------------------------------------------------------

resource "snowflake_warehouse" "compute_wh" {
  name                = "COMPUTE_WH"
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  min_cluster_count   = 1
  max_cluster_count   = 1
  comment             = "ETL warehouse: used by dbt and Snowpipe/Tasks to move data through the medallion layers. Kept small since ETL load is predictable and moderate."
}

resource "snowflake_warehouse" "analytics_wh" {
  name                = "ANALYTICS_WH"
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  min_cluster_count   = 1
  max_cluster_count   = 1
  comment             = "Analytics warehouse: reserved for BI dashboards and ad-hoc analyst queries against GOLD, kept separate from ETL so heavy dashboard usage never delays or competes with the pipeline."
}


## -----------------------------------------------------------------
## DEV DATABASE
## -----------------------------------------------------------------

resource "snowflake_database" "player_analytics_dev" {
  name    = "PLAYER_ANALYTICS"
  comment = "Development database for player data extracted from MySQL/Aurora via a lightweight Glue extract-only job."
}

resource "snowflake_schema" "dev_raw" {
  database = snowflake_database.player_analytics_dev.name
  name     = "RAW"
  comment  = "Raw CSVs loaded via Snowpipe from S3, exactly as Glue extracted them from MySQL (dev)."
}

resource "snowflake_schema" "dev_bronze" {
  database = snowflake_database.player_analytics_dev.name
  name     = "BRONZE"
  comment  = "Basic type casting only. No deduplication, no business rules (dev)."
}

resource "snowflake_schema" "dev_silver" {
  database = snowflake_database.player_analytics_dev.name
  name     = "SILVER"
  comment  = "Business rules applied here: code mapping, deduplication by business key. Moved out of Glue/PySpark into dbt (dev)."
}

resource "snowflake_schema" "dev_gold" {
  database = snowflake_database.player_analytics_dev.name
  name     = "GOLD"
  comment  = "Business-ready dimensional model, for direct querying by BI/dashboard tools via ANALYTICS_WH (dev)."
}


## -----------------------------------------------------------------
## PROD DATABASE
## -----------------------------------------------------------------

resource "snowflake_database" "player_analytics_prod" {
  name    = "PLAYER_ANALYTICS_PROD"
  comment = "Production database for player data extracted from MySQL/Aurora via a lightweight Glue extract-only job."
}

resource "snowflake_schema" "prod_raw" {
  database = snowflake_database.player_analytics_prod.name
  name     = "RAW"
  comment  = "Raw CSVs loaded via Snowpipe from S3, exactly as Glue extracted them from MySQL (prod)."
}

resource "snowflake_schema" "prod_bronze" {
  database = snowflake_database.player_analytics_prod.name
  name     = "BRONZE"
  comment  = "Basic type casting only. No deduplication, no business rules (prod)."
}

resource "snowflake_schema" "prod_silver" {
  database = snowflake_database.player_analytics_prod.name
  name     = "SILVER"
  comment  = "Business rules applied here: code mapping, deduplication by business key. Moved out of Glue/PySpark into dbt (prod)."
}

resource "snowflake_schema" "prod_gold" {
  database = snowflake_database.player_analytics_prod.name
  name     = "GOLD"
  comment  = "Business-ready dimensional model, for direct querying by BI/dashboard tools via ANALYTICS_WH (prod)."
}


## -----------------------------------------------------------------
## STORAGE INTEGRATION (Snowflake <-> S3 bridge)
## -----------------------------------------------------------------

## This resource creates the bridge that lets Snowflake read files
## from the S3 bucket securely, without ever handling AWS access keys
## directly. Snowflake authenticates via an IAM role trust relationship
## instead of static credentials -- more secure, and the standard
## pattern for external stages in production.
##
## NOTE: storage_aws_role_arn below is a PLACEHOLDER on first apply.
## Snowflake needs to exist first so it can generate the external ID
## and IAM user ARN that the real AWS role's trust policy depends on --
## this gets corrected in a follow-up step once those values are known.
resource "snowflake_storage_integration" "s3_player_data" {
  name    = "S3_PLAYER_DATA_INTEGRATION"
  comment = "Bridges Snowflake to the dlk-olimpo S3 bucket, scoped only to the dwh_player_csv prefix used by this project."

  storage_provider = "S3"
  enabled          = true

  storage_allowed_locations = [
    "s3://dlk-olimpo/raw/PE/DWH/dwh_player_csv/"
  ]

  storage_aws_role_arn = "arn:aws:iam::211125514336:role/snowflake-s3-player-data-role"
}
