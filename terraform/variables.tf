variable "snowflake_password" {
  description = "Snowflake password, loaded from TF_VAR_snowflake_password"
  type        = string
  sensitive   = true
}


# Email address to receive pipeline failure notifications via SNS.
# Passed as TF_VAR_alert_email, never hardcoded (same pattern as snowflake_password).
variable "alert_email" {
  description = "Email address subscribed to the pipeline failure SNS topic"
  type        = string
  sensitive   = true
}