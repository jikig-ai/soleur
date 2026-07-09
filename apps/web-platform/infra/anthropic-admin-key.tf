# #cost-attribution (plan Phase 3 / Infrastructure §) — ANTHROPIC_ADMIN_KEY.
#
# Read-only org-billing Admin key (sk-ant-admin01-…) that the daily
# cron-anthropic-cost-report reads at runtime to pull the Anthropic Admin cost &
# usage API. It CANNOT spend or read conversations — the blast-radius control is
# its read-only scope, not env isolation (the whole web-platform process reads
# soleur/prd; plan R-E). Covered by `API_KEY_RE` (lib/safety/redaction-
# allowlist.ts:71) so it never reaches a log/Sentry payload.
#
# Approach B (mirrors inngest-betterstack-token.tf / github-app.tf): a
# `doppler_secret` whose value comes from a sensitive, NO-DEFAULT var sourced
# from Doppler `prd_terraform` — only this one admin key enters
# terraform.tfstate (NOT a ~116-secret soleur/prd map). `ignore_changes=[value]`
# leaves rotation to the source of truth (Anthropic console / Doppler), not this
# file — the name persists so the runtime read is stable.
#
# ‼️ SEQUENCING (Sharp Edge — operator-mint-tf-var-must-sequence-before-auto-
# applied-iac): `apply-web-platform-infra.yml` resolves ALL root vars BEFORE
# `-target` pruning, so a no-default `var.anthropic_admin_key` that is ABSENT
# from `prd_terraform` fails the WHOLE merge-apply. Therefore this file lands in
# a follow-up that merges AFTER the vendor-console key mint + the
# `TF_VAR_anthropic_admin_key` provisioning into `prd_terraform`. The cron code
# (Phases 1-4) merges first and self-reports `anthropic-admin-key-missing`
# benignly until the key lands. `dev` is intentionally NOT provisioned (the dark
# path self-reports key-missing; hr-dev-prd-distinct).

resource "doppler_secret" "anthropic_admin_key" {
  project    = "soleur"
  config     = "prd"
  name       = "ANTHROPIC_ADMIN_KEY"
  value      = var.anthropic_admin_key
  visibility = "masked"

  lifecycle {
    # Rotation is managed at the source of truth (Anthropic console / Doppler),
    # not this file — mirrors github-app.tf / inngest-betterstack-token.tf. Treat
    # any tfstate exposure as an admin-key-rotation trigger (plan R-G).
    ignore_changes = [value]
  }
}
