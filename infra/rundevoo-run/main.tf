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
  # use_lockfile (S3 backend) landed in Terraform 1.10; a lower floor would
  # admit versions that hard-error on init. Sibling roots carry the same stale
  # floor — tracked in #12999.
  required_version = ">= 1.10"
}

provider "cloudflare" {
  # Explicit var binding: the shared infra-validation leg runs under
  # `doppler run --name-transformer tf-var` over prd_terraform (exports
  # TF_VAR_cf_api_token_rundevoo); this root's own apply/drift legs export the
  # same TF_VAR name directly from CF_API_TOKEN_RUNDEVOO. Do NOT rely on a
  # provider env-var default — an explicitly-bound api_token never reads
  # CLOUDFLARE_API_TOKEN (that name is exported only for the set-equality
  # REST probe, which takes a raw bearer).
  api_token = var.cf_api_token_rundevoo

  # 5xx retry budget ~7.75min/request (15+30+60+120+120+120s vs ~7s v4
  # default) — rides out multi-minute Cloudflare API blips at plan (#10643).
  # v5 renames this trio `max_retries`; carry the budget across a migration.
  retries     = 6
  min_backoff = 15
  max_backoff = 120
}
