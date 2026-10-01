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
  description = "Bootstrap-only Cloudflare admin token with R2:Edit + API Tokens:Edit scopes. Used by the null_resource provisioner to PUT the bucket lock rule via the CF native REST API. Same value as cf_api_token at bootstrap time; the split exists to localize the future deletion when FW1 swaps the null_resource shim for a native TF resource. Admin tokens are ephemeral one-hour creds (see bootstrap.sh header), so triggers.token_hash guarantees a re-fire on every bootstrap rather than detecting drift; the CF Lock Rules PUT is idempotent so re-fires are no-ops state-wise."

  # Empty default so a credential-less `terraform plan` does not abort, mirroring the
  # r2_admin_* siblings below. Required because this token is minted ephemerally by
  # bootstrap.sh (one-hour cred, exported as TF_VAR_cf_admin_token at bootstrap.sh:124)
  # and therefore has no standing value in Doppler prd_terraform — verified absent
  # 2026-08-20. Without a default, infra-validation.yml's `plan` matrix job aborts with
  # "No value for required variable" for EVERY change under apps/cla-evidence/infra/**,
  # including docs-only ones. That job is path-filtered, so it had never run to
  # completion and the breakage was latent until #7624 touched this directory.
  #
  # SAFE BECAUSE infra-validation.yml IS PLAN-ONLY for this root: it has no
  # `terraform apply` step (verified — its three "apply"-named steps are
  # deploy-script-tests suites that TEST apply scripts). A real bootstrap always
  # supplies the value, so the default is never the applied one. If an apply step is
  # ever added here, this default must be revisited: an empty token would reach the
  # provisioner rather than failing fast.
  #
  # A plan run will show object_lock.tf's null_resource re-firing (triggers.token_hash
  # = sha256(var.cf_admin_token)). That is the documented steady state per the
  # description above — it re-fires on every bootstrap by design — not a new signal.
  default = ""
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
