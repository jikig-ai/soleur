output "bucket_name" {
  value       = cloudflare_r2_bucket.cla_evidence.name
  description = "R2 bucket name."
}

output "bucket_endpoint" {
  value       = "${var.r2_s3_endpoint}/${cloudflare_r2_bucket.cla_evidence.name}"
  description = "S3-compatible endpoint URL for the bucket."
}

output "object_write_token_id" {
  value       = cloudflare_api_token.cla_evidence_object_write.id
  description = "Token id (used as R2 S3-compat Access Key ID per Cloudflare's HMAC-derivation contract: access_key_id = token id, secret_access_key = sha256(token value))."
  sensitive   = false
}

output "object_write_token_value" {
  value       = cloudflare_api_token.cla_evidence_object_write.value
  description = "Object-write API token value. Sync to Doppler `prd_cla` immediately and rotate on any leak signal. The S3-compat secret-key is derived as sha256(value); the bearer-value itself is NOT pushed as a credential."
  sensitive   = true
}

output "state_write_token_value" {
  value       = cloudflare_api_token.cla_evidence_state_write.value
  description = "State-write API token. Sync to Doppler `prd_terraform` (or the operator's local CI doppler scope)."
  sensitive   = true
}
