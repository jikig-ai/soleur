output "bucket_name" {
  value       = cloudflare_r2_bucket.cla_evidence.name
  description = "R2 bucket name."
}

output "bucket_endpoint" {
  value       = "${var.r2_s3_endpoint}/${cloudflare_r2_bucket.cla_evidence.name}"
  description = "S3-compatible endpoint URL for the bucket."
}

output "object_write_token_value" {
  value       = cloudflare_api_token.cla_evidence_object_write.value
  description = "Object-write API token. Sync to Doppler `prd_cla` immediately and rotate on any leak signal."
  sensitive   = true
}

output "state_write_token_value" {
  value       = cloudflare_api_token.cla_evidence_state_write.value
  description = "State-write API token. Sync to Doppler `prd_terraform` (or the operator's local CI doppler scope)."
  sensitive   = true
}
