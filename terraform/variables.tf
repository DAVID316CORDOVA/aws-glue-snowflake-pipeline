variable "snowflake_password" {
  description = "Snowflake password, loaded from TF_VAR_snowflake_password"
  type        = string
  sensitive   = true
}
