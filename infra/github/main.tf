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

# Provider auth: App-installation auth via the soleur-ai App (id 3261325,
# org-wide installation 122213433 on jikig-ai). The integrations/github
# provider exchanges App credentials for a short-lived installation token at
# each `terraform plan/apply`. Migrated from PAT auth (the eliminated
# `gh_token` variable) in #4384 per AGENTS.core.md hr-github-app-auth-not-pat,
# mirroring the apps/web-platform/infra/main.tf:72-79 pattern landed by #4144.
# App credentials live in Doppler `prd_terraform` as GITHUB_APP_ID +
# GITHUB_APP_PRIVATE_KEY; rotation is App-side only. The App MUST have
# Administration:Write permission (required for ruleset writes); verify at
# https://github.com/organizations/jikig-ai/settings/installations/122213433
# if a plan errors with 401 "Resource not accessible by integration".
provider "github" {
  owner = "jikig-ai"
  app_auth {
    id              = var.github_app_id
    installation_id = "122213433"
    pem_file        = var.github_app_private_key
  }
}
