# Closes #4195. Dedicated write-capable Doppler service token for the
# post-apply `Sync CF Access CI-SSH service token to Doppler` step in
# `.github/workflows/apply-web-platform-infra.yml`. The existing
# `secrets.DOPPLER_TOKEN` is `prd_terraform`-scoped READ-only; the sync
# step needs `secrets:write`. Mirrors the in-band mint pattern from
# `kb-drift.tf:65-86` with two diffs: (a) `access = "read/write"`,
# (b) scoped to `prd_terraform` (not `prd_kb_drift_walker`).
#
# Blast radius: token grants write to `prd_terraform` ONLY (Cloudflare,
# Hetzner, GitHub-App, Inngest, Resend creds, `var.admin_ips`). Net
# incremental write surface vs. existing `var.doppler_token_tf`
# (workplace-scope) is ZERO — this is a strict narrowing.
#
# Rotation: `terraform apply -replace=doppler_service_token.write`.
# The new key value MUST propagate to
# `github_actions_secret.doppler_token_write.plaintext_value` — this
# file deliberately omits `lifecycle.ignore_changes = [plaintext_value]`
# on that resource so rotation reaches the consumer in the same apply
# (mirrors `kb-drift.tf:78-86`).
#
# State storage: `doppler_service_token.write.key` is `Computed +
# Sensitive` per the Doppler provider; the value lands in
# `terraform.tfstate` (R2-backed, encrypted bucket — same posture as
# `doppler_service_token.kb_drift.key`) on create and CANNOT be re-read
# from the Doppler API (provider source: `// "key" cannot be read after
# initial creation`). State-loss is unrecoverable; recovery is
# `terraform apply -replace=doppler_service_token.write`, which mints a
# new token and orphans the old one (still valid; revoke manually via
# `doppler configs tokens revoke`).
#
# Bootstrap cycle: on the first apply after this file lands, the GH
# Actions runner has no `DOPPLER_TOKEN_WRITE` secret yet — the
# precondition guard in the sync step's workflow degrades to
# `::warning::` and skips. Subsequent applies consume the published
# secret normally. See the new step `Verify DOPPLER_TOKEN_WRITE present`
# in `apply-web-platform-infra.yml`.
#
# autonomy-considered: provider-mint-applied (App auth + doppler_service_token).

resource "doppler_service_token" "write" {
  project = "soleur"
  config  = "prd_terraform"
  name    = "ci-tf-write"
  access  = "read/write"
}

resource "github_actions_secret" "doppler_token_write" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_WRITE"
  plaintext_value = doppler_service_token.write.key
}
