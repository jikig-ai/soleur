variable "cf_account_id" {
  type        = string
  description = "Cloudflare account ID (Jikigai)."
}

variable "cf_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token with R2 admin + API tokens management. Used by Terraform; not passed to workflows."
}

variable "r2_s3_endpoint" {
  type        = string
  description = "R2 S3-compatible endpoint (https://<account>.r2.cloudflarestorage.com)."
  default     = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com"
}

variable "r2_admin_access_key_id" {
  type        = string
  sensitive   = true
  description = "Pre-existing R2 admin access key for the null_resource provisioner that sets bucket Object Lock configuration. Sourced from Doppler at apply time. Not stored in state by the null_resource (only its hash trigger)."
}

variable "r2_admin_secret_access_key" {
  type        = string
  sensitive   = true
  description = "Pre-existing R2 admin secret. See r2_admin_access_key_id."
}
