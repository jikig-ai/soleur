# Two scoped Cloudflare API tokens for the CLA evidence layer.
#
# Defense-in-depth: object-write and state-write scopes are split so a compromise
# of the workflow's object-write token cannot rewrite the Terraform state file.
# Per COO recommendation in the plan's brainstorm domain assessment.
#
# Bucket-scoped, not account-scoped: per multi-agent review on PR #3201
# (architecture-strategist + security-sentinel + user-impact-reviewer
# convergence), each token's `resources` map names exactly the bucket it needs.
# Resource-string format `com.cloudflare.edge.r2.bucket.<account>_<jurisdiction>_<bucket>`
# is the Cloudflare R2 token-scoping convention (verified against
# Cyb3r-Jak3/terraform-cloudflare-r2-api-token module and the public R2 token
# API). Jurisdiction is `default` for the standard (non-EU/FedRAMP) tier; our
# `weur` bucket location is a placement hint, not a jurisdiction.
#
# R2 tokens do NOT support prefix-level scoping — bucket is the finest grain.
# Token #2 therefore covers the whole `soleur-terraform-state` bucket (which
# also holds other Terraform roots' state). Tightening below bucket level would
# require a dedicated state bucket per root; deferred as out-of-scope for the
# CLA evidence layer.
#
# NO IP-allowlist: per plan-review convergence (DHH F1 + Code-Simplicity F2), the
# bucket holds already-public data (GitHub identities), and a recurring CIDR
# refresh chore was judged not to earn its keep at this scope.

data "cloudflare_api_token_permission_groups" "all" {}

# Token #1: object-write only on the soleur-cla-evidence bucket.
# Used by the .github/workflows/cla-evidence.yml sidecar workflow at sign-time,
# and by the .github/workflows/cla-evidence-timestamp.yml monthly cron.
# Synced to Doppler `prd_cla` config; surfaced to GitHub Actions as
# DOPPLER_TOKEN_CLA → R2_CLA_EVIDENCE_ACCESS_KEY_ID + R2_CLA_EVIDENCE_SECRET.
resource "cloudflare_api_token" "cla_evidence_object_write" {
  name = "soleur-cla-evidence-object-write"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.r2["Workers R2 Storage Bucket Item Write"],
    ]
    resources = {
      "com.cloudflare.edge.r2.bucket.${var.cf_account_id}_default_${cloudflare_r2_bucket.cla_evidence.name}" = "*"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Token #2: state-write only on the soleur-terraform-state bucket (which holds
# this root's `cla-evidence/terraform.tfstate` key alongside other roots' state).
# Used exclusively by `terraform apply` from this root.
# Distinct from token #1 — compromise of #1 cannot pivot to state rewrite.
resource "cloudflare_api_token" "cla_evidence_state_write" {
  name = "soleur-cla-evidence-tfstate-write"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.r2["Workers R2 Storage Bucket Item Write"],
      data.cloudflare_api_token_permission_groups.all.r2["Workers R2 Storage Bucket Item Read"],
    ]
    resources = {
      "com.cloudflare.edge.r2.bucket.${var.cf_account_id}_default_soleur-terraform-state" = "*"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Read access for the inspection runbook (Phase 7 / GDPR retrieval) is NOT
# created here. Per plan, operator generates an ad-hoc 24h-TTL token via the
# Cloudflare dashboard at retrieval time, scoped read-only to the bucket, and
# revokes after use. Keeping the standing token surface minimal.
