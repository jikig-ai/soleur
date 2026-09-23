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
# runbook Step 2.1 for the procedure. Both drift planes are now detected by
# apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts:
# App-declared-vs-manifest (existing block) and installation-grant-vs-manifest
# (the class that produced #4173 — checked in the same handler, reusing the
# same App-JWT via createAppJwtOctokit() and the pure-TS manifest diff at
# apps/web-platform/server/github/manifest-diff.ts).
#
# Why ignore_changes on the 2 operator-supplied secrets: rotation via the
# Doppler UI is invisible to subsequent `terraform plan` (the provider
# skips the value read-back). NO ignore_changes on the random_id-derived
# webhook secret — rotation is operator-explicit via `terraform apply
# -replace=...`. Mirrors the policy from inngest.tf:97-104.

# --- #8209 / ADR-239: FORGET the two App-identity mirrors --------------------
#
# READ THIS BEFORE TOUCHING EITHER BLOCK BELOW. The two resources these replace pinned
# `config = "prd"`, which means they were NOT a Terraform bookkeeping copy of the App
# key — they WERE the soleur-ai App's live runtime identity, the key the web app reads
# to mint an installation token for every connected user. Destroying them breaks every
# connected user's GitHub connection and every inbound webhook, with no rollback beyond
# the operator pasting a key back by hand. `ignore_changes = [value]` protected the
# value; nothing protected the resource.
#
# WHY THEY GO. Web-platform state should not hold a copy of an App key at all: the
# `prd_terraform` backend keys read that state object (M7), so the mirror put the key
# one `terraform show` away from any branch workflow. Terraform stops MANAGING the
# secrets; Doppler `prd` keeps its values, byte-for-byte, and the App keeps working.
#
# WHY `destroy = false` IS LOAD-BEARING. Without it `removed` is a DELETE. With it,
# Terraform plans "will no longer be managed by Terraform, but will not be destroyed".
#
# WHY THE `-target=` LINES STAY. apply-web-platform-infra.yml applies this root with a
# `-target=` allow-list, and a `removed` block is planned ONLY when its address is
# targeted. Deleting `-target=doppler_secret.github_app_private_key` (and `_id`) would
# leave the resources in state with no HCL declaring them — orphaned under management,
# which the next UNTARGETED apply destroys. So the dangling-looking target lines are the
# opposite of dead code until the forget has actually applied. Removing them is part of
# the R6 follow-up, after the operator confirms the forget landed.
#
# HOW THE ADDRESSES WERE OBTAINED. Copied from `terraform state list`, not typed. A
# misspelled `from` address leaves the real resource unclaimed by any `removed` block
# while its resource block is gone — which Terraform plans as a plain DESTROY.
# tests/scripts/test-infra-privileged-tier-census.sh (Guard 4) asserts all of this.
removed {
  from = doppler_secret.github_app_id

  lifecycle {
    destroy = false
  }
}

removed {
  from = doppler_secret.github_app_private_key

  lifecycle {
    destroy = false
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
