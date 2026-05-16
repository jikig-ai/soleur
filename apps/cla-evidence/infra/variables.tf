variable "cf_account_id" {
  type        = string
  description = "Cloudflare account ID (Jikigai)."
}

variable "cf_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token with R2 admin + API tokens management. Used by Terraform; not passed to workflows."
}

variable "cf_admin_token" {
  type        = string
  sensitive   = true
  description = "Bootstrap-only Cloudflare admin token with R2:Edit + API Tokens:Edit scopes. Used by the null_resource provisioner to PUT the bucket lock rule via the CF native REST API. Same value as cf_api_token in practice; held as a distinct variable so the lock-rule trigger hash detects token rotation independently of provider-level config."
}

variable "r2_s3_endpoint" {
  type        = string
  description = "R2 S3-compatible endpoint (https://<account>.r2.cloudflarestorage.com)."
  default     = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com"
}

variable "r2_admin_access_key_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "[DEPRECATED 2026-05-16] Previously used by the Object Lock null_resource against the S3-compat API. R2 does not implement PutObjectLockConfiguration, so the provisioner now PUTs to the CF native Lock Rules endpoint using cf_admin_token. Kept with an empty default so legacy TF_VAR injection from old Doppler configs does not fail terraform plan."
}

variable "r2_admin_secret_access_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "[DEPRECATED 2026-05-16] See r2_admin_access_key_id."
}
