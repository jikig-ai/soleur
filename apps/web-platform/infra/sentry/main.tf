# Backend mirrors apps/web-platform/infra/main.tf — same R2 bucket, distinct
# state key so this root and the main web-platform root never share locks
# (R2 has no S3 conditional writes; use_lockfile = false).
terraform {
  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "web-platform/sentry/terraform.tfstate"
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

# Provider auth: SENTRY_AUTH_TOKEN env var (GitHub repo secret in CI; local
# user token or internal-integration token from de.sentry.io for operator
# imports — see ADR-031 §local-token).
#
# base_url override targets the EU ingest cluster. Sentry has US (sentry.io)
# and EU (de.sentry.io) clusters; Soleur's organization is in DE per Article
# 30 register PA8 §(e). Provider docs do not explicitly enumerate de.sentry.io;
# Phase 0.1.5 of the plan validated DE region support against a scratch
# project before this root landed.
provider "sentry" {
  base_url = var.sentry_region == "de" ? "https://de.sentry.io/api/" : "https://sentry.io/api/"
}

# Cross-resource defaults — both issue alerts and cron monitors live in the
# same project; a data lookup keeps the slug-vs-internal-id mapping in sync
# with the dashboard without hardcoding an internal id.
data "sentry_project" "web_platform" {
  organization = var.sentry_org
  slug         = var.sentry_project
}
