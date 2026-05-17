# Backend mirrors apps/web-platform/infra/sentry/main.tf -- same R2 bucket,
# distinct state key so this root and the per-app roots never share locks
# (R2 has no S3 conditional writes; use_lockfile = false).
terraform {
  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "github/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = false # R2 does not support S3 conditional writes
  }
}

# Provider auth: GH_RULESET_PAT (Doppler prd_terraform) becomes TF_VAR_gh_token
# via `doppler run --name-transformer tf-var --`. Fine-grained PAT scoped to
# jikig-ai/soleur with Administration: Read+Write only. Rotation cadence
# (90 days) documented in README.md Phase 4.
provider "github" {
  owner = var.gh_owner
  token = var.gh_token
}
