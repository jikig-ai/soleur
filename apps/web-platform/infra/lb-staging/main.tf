# (#11181 F3) THE LB-STAGING THROWAWAY ROOT — a SEPARATE Terraform root for the Part-2
# staging convert (cf-lb-a-record-gaplessness-verify.md). Same separation argument as
# rung2-rehearsal/main.tf: `-target` is transitive on dependencies, so staging resources
# living in the parent root would drag hcloud_server.web["web-1"] into every plan
# closure; a separate state file makes reaching prod a structural impossibility. The
# throwaway hostname is lb-staging.soleur.ai — nothing here may name app.soleur.ai
# (the gate asserts it).
#
# WHAT THE SEPARATION DOES **NOT** ISOLATE (rung2 doctrine, ADR-149 DC-6): this root
# shares the production soleur.ai ZONE, the prod hcloud project, and the prod Doppler
# project. A `cloudflare_record` create here IS a prod-zone write — which is why the
# plan graders pin after.name/type/proxied, not just addresses. Reaching a managed
# prod STATE address is impossible (disjoint key); reaching the zone is not.
# Residuals after teardown: monitor/pool objects orphaned by a partial destroy are
# NOT covered by the zone-clean curl — re-dispatch staging-teardown (idempotent) or
# sweep via CF API. data.hcloud_server.web_1 reads the name "soleur-web-platform"
# (server.tf naming expression) — a web-1 rename/replace fails this root's plan
# (fail-closed, intended).
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
    use_lockfile                = false
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    # R2 does not support S3 conditional writes — no state lock; the shared
    # concurrency group on cf-lb-overlay.yml is the serializer (same as parent).
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 4.52.7" # v4 keys — PINNED to the parent root's locked version: the rehearsal attests the bytes GA will run
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "= 1.63.0" # pinned to the parent root's locked version
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
