terraform {
  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "cla-evidence/terraform.tfstate"
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
  required_version = ">= 1.6"
}

provider "cloudflare" {
  api_token = var.cf_api_token

  # 5xx retry budget ~7.75min/request (15+30+60+120+120+120s vs ~7s v4
  # default) — rides out multi-minute Cloudflare API blips at plan (#10643).
  # v5 renames this trio `max_retries`; carry the budget across a migration.
  retries     = 6
  min_backoff = 15
  max_backoff = 120
}
