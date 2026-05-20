# PR-H (#3244) — GitHub App secrets for the multi-source webhook ingress.
# ADR-036 (apps/web-platform/infra/main.tf-referenced).
#
# Provisions:
#   - 4 operator-supplied doppler_secret resources in `prd` for the GitHub
#     App's identity material (App ID, PEM, Client ID, Client Secret).
#     Operator creates the App once at github.com/settings/apps/new (single
#     manual gate per hr-never-label-any-step-as-manual-without — vendor
#     limit: github.com/settings/apps/new requires a human session, no API).
#     `terraform apply` against these resources runs automatically post-merge
#     via `.github/workflows/apply-web-platform-infra.yml` (closes #4114).
#   - 1 random_id resource for the webhook secret (Soleur-generated; rotation
#     = `terraform apply -replace=random_id.github_webhook_secret`).
#   - 1 doppler_secret resource publishing the webhook secret to `prd`.
#   - github_repository.webhook_url output for the operator to paste back
#     into the GitHub App configuration after first apply (closes the loop).
#
# Why ignore_changes on the 4 operator-supplied secrets: rotation via the
# Doppler UI is invisible to subsequent `terraform plan` (the provider
# skips the value read-back). NO ignore_changes on the random_id-derived
# webhook secret — rotation is operator-explicit via `terraform apply
# -replace=...`. Mirrors the policy from inngest.tf:97-104.

resource "doppler_secret" "github_app_id" {
  project    = "soleur"
  config     = "prd"
  name       = "GITHUB_APP_ID"
  value      = var.github_app_id
  visibility = "masked"

  lifecycle {
    # dev/prd isolation: each doppler_secret pins config = "prd" explicitly.
    # The resource cannot land in dev without an edit to this file (caught
    # at PR review). Mirrors the pattern from inngest.tf.
    ignore_changes = [value]
  }
}

resource "doppler_secret" "github_app_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GITHUB_APP_PRIVATE_KEY"
  value      = var.github_app_private_key
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "doppler_secret" "github_app_client_id" {
  project    = "soleur"
  config     = "prd"
  name       = "GITHUB_APP_CLIENT_ID"
  value      = var.github_app_client_id
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "doppler_secret" "github_app_client_secret" {
  project    = "soleur"
  config     = "prd"
  name       = "GITHUB_APP_CLIENT_SECRET"
  value      = var.github_app_client_secret
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}

# Webhook secret — Soleur-generated. Rotate via:
#   terraform apply -replace=random_id.github_webhook_secret
# AFTER rotating, paste the new value into the GitHub App config (UI).
resource "random_id" "github_webhook_secret" {
  byte_length = 32
}

resource "doppler_secret" "github_app_webhook_secret" {
  project    = "soleur"
  config     = "prd"
  name       = "GITHUB_APP_WEBHOOK_SECRET"
  value      = "ghwh-${random_id.github_webhook_secret.hex}"
  visibility = "masked"
  # NO ignore_changes — rotation is operator-explicit via -replace.
}
