terraform {
  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "rundevoo-run/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = false # R2 has no S3 conditional writes; single-writer apply only.
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.7"
}

provider "cloudflare" {
  # Explicit var binding: every consumer leg runs under
  # `doppler run --name-transformer tf-var` over prd_terraform, which exports
  # TF_VAR_cf_api_token_rundevoo. Do NOT rely on a provider env-var default —
  # the shared legs do not export CLOUDFLARE_API_TOKEN (workflows map it
  # explicitly from CF_API_TOKEN_RUNDEVOO where a raw REST call needs it).
  api_token = var.cf_api_token_rundevoo

  # 5xx retry budget ~7.75min/request (15+30+60+120+120+120s vs ~7s v4
  # default) — rides out multi-minute Cloudflare API blips at plan (#10643).
  # v5 renames this trio `max_retries`; carry the budget across a migration.
  retries     = 6
  min_backoff = 15
  max_backoff = 120
}
