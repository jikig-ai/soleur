# PR-H (#3244) — GitHub App secrets for the multi-source webhook ingress.
# ADR-036 (apps/web-platform/infra/main.tf-referenced).
#
# Provisions:
#   - 2 operator-supplied doppler_secret resources in `prd` for the GitHub
#     App's identity material (App ID, PEM). Operator creates the App once
#     at github.com/settings/apps/new (single manual gate per
#     hr-never-label-any-step-as-manual-without — vendor limit: App creation
#     requires a human session, no API). `terraform apply` against these
#     resources runs automatically post-merge via
#     `.github/workflows/apply-web-platform-infra.yml` (closes #4114).
#   - 1 random_id resource for the webhook secret (Soleur-generated; rotation
#     = `terraform apply -replace=random_id.github_webhook_secret`).
#   - 1 doppler_secret resource publishing the webhook secret to `prd`.
#   - github_repository.webhook_url output for the operator to paste back
#     into the GitHub App configuration after first apply (closes the loop).
#
# Post-#4150: the github_app_client_id / github_app_client_secret resources
# were deleted — never read by any app code (TS/TSX grep returned zero);
# the values are leftover OAuth plumbing not used by the App-installation
# webhook flow. The App-installation auth in main.tf supersedes the need
# for OAuth client credentials.
#
# Post-#4173: adding a key to default_permissions in github-app-manifest.json
# requires founder re-acceptance via the GitHub UI (no API — vendor limit,
# vendor-authorization-scope class of the operator-only canonical list). See
# runbook Step 2.1 for the procedure. Drift-guard at scheduled-github-app-
# drift-guard.yml detects App-declared-vs-manifest divergence; installation-
# grant-vs-manifest divergence (the class that produced #4173) is NOT yet
# covered — see follow-up issue.
#
# Why ignore_changes on the 2 operator-supplied secrets: rotation via the
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
