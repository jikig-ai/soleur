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

# --- #8209 / ADR-241: FORGET the repo-secret write path ----------------------
#
# `DOPPLER_TOKEN_WRITE` is a REPO secret with read/write on `soleur/prd_terraform`, so
# any workflow on any branch of this public repository can name it. That is a WRITE into
# the config a Tier-B apply reads, and `doppler run` overrides existing environment
# variables by default — so a branch actor could plant `HCLOUD_TOKEN=<their account>`
# and a later main-branch apply would plan against it. (The `--preserve-env` flag on
# every Tier-B `doppler run` closes that independently; this closes the other end.)
#
# FORGET, NOT DESTROY, and that is what makes the merge safe. The token stays live and
# the repo secret stays published until the operator mints a replacement into the
# `infra-privileged` environment (operator step O6) and deletes the repo secret (O11).
# Destroying either here would break every Tier-B job the moment this PR merges, before
# any operator step has run. The consumers are already Tier-B jobs, so the move is a
# carrier change, not a permission change.
#
# The `-target=github_actions_secret.doppler_token_write` line at
# apply-web-platform-infra.yml stays for the same reason as in github-app.tf: a
# `removed` block is only planned when its address is targeted, and an untargeted
# forget leaves the resource orphaned under management.
removed {
  from = doppler_service_token.write

  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_secret.doppler_token_write

  lifecycle {
    destroy = false
  }
}
