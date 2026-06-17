# #5480 — receiving-scoped Resend key for inbound-mail body fetch.
# Follow-up to #5468 (degraded-finalize tail merged in PR #5475); split per
# ADR-065 (operator-mint no-default TF var must be provisioned in prd_terraform
# BEFORE this IaC merges, else the auto-applied apply fails resolving the var
# before -target pruning).
#
# Operator-supplied-secret pattern — mirrors github-app.tf:40-80 (and
# inngest.tf:63-107). The key is minted in the Resend dashboard (no creation
# API — vendor limit) and set as TF_VAR_resend_receiving_api_key in Doppler
# prd_terraform; this resource publishes it to the `prd` Doppler config where
# the Next.js app reads it at runtime (fetch-received-email.ts).
#
# NOT threaded into the cloud-init monitor env files (disk/resource/container
# monitors are send-only and must not carry the receiving key — least-privilege,
# #5480). Those scripts continue to read only RESEND_API_KEY.
#
# Why ignore_changes on value: rotation via the Resend dashboard + Doppler is
# invisible to subsequent `terraform plan` (the provider skips the value
# read-back), so without ignore_changes every apply would churn this secret.
# Same policy as the operator-supplied secrets in github-app.tf / inngest.tf.

resource "doppler_secret" "resend_receiving_api_key" {
  project    = "soleur"
  config     = "prd"
  name       = "RESEND_RECEIVING_API_KEY"
  value      = var.resend_receiving_api_key
  visibility = "masked"

  lifecycle {
    # dev/prd isolation: config = "prd" pinned explicitly; cannot land in dev
    # without an edit to this file (caught at PR review). Mirrors github-app.tf.
    ignore_changes = [value]
  }
}
