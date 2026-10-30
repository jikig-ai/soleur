# (#11181 F3) THE LB-STAGING THROWAWAY ROOT — a SEPARATE Terraform root for the Part-2
# staging convert (cf-lb-a-record-gaplessness-verify.md). Same separation argument as
# rung2-rehearsal/main.tf: `-target` is transitive on dependencies, so staging resources
# living in the parent root would drag hcloud_server.web["web-1"] into every plan
# closure; a separate state file makes reaching prod a structural impossibility. The
# throwaway hostname is lb-staging.soleur.ai — nothing here may name app.soleur.ai
# (the gate asserts it).
#
# Dispatched ONLY by .github/workflows/cf-lb-overlay.yml (workflow_dispatch arms).
# Its own state key; it joins the parent's workflow-level
# `terraform-apply-web-platform-host` concurrency group because R2 has no state lock.

terraform {
  backend "s3" {
    bucket = "soleur-terraform-state"
    # A DISTINCT KEY, directory-shaped like the rung2-rehearsal precedent.
    key                         = "web-platform/lb-staging/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    # R2 does not support S3 conditional writes — no state lock; the shared
    # concurrency group on cf-lb-overlay.yml is the serializer (same as parent).
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0" # v4 keys (default_pool_ids/fallback_pool_id) — NOT v5 names
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }

  required_version = ">= 1.7"
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cf_api_token

  # 5xx retry budget ~7.75min/request — mirrors the parent root's provider block
  # (main.tf) so a Cloudflare API blip does not fail the convert mid-probe.
  retries     = 6
  min_backoff = 15
  max_backoff = 120
}
