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
# internal-integration token from `https://${var.sentry_org}.sentry.io/settings/developer-settings/`
# for operator imports — see ADR-031 §local-token).
#
# base_url targets the org-subdomain (`https://<org-slug>.sentry.io/api/`), NOT
# `https://eu.sentry.io/api/` — the regional EU API host silently rewrites
# org slugs ending in `-eu` to the literal `eu` org via an activeorg-cookie
# hijack (302 → 401 cascade), breaking every Terraform read/write. The
# org-subdomain is the only base_url shape that works for slug-scoped paths
# regardless of slug. See learning
# `knowledge-base/project/learnings/2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`
# and ADR-031 §Cluster / Host Glossary (API row).
#
# DSN ingest cluster remains `de.sentry.io` (DE residency) per Article 30
# PA8 §(e) — that's a separate hostname class from the API/dashboard
# base_url, see ADR-031 glossary.
provider "sentry" {
  base_url = "https://${var.sentry_org}.sentry.io/api/"
}

# Cross-resource defaults — both issue alerts and cron monitors live in the
# same project; a data lookup keeps the slug-vs-internal-id mapping in sync
# with the dashboard without hardcoding an internal id.
data "sentry_project" "web_platform" {
  organization = var.sentry_org
  slug         = var.sentry_project
}
