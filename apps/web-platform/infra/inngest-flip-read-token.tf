# Ref #9927 item 8. A READ-ONLY Doppler service token for `soleur-inngest/prd`, published as the repo
# secret DOPPLER_TOKEN_INNGEST_FLIP_READ. Its one consumer is the `inngest_host_replace` inherited-done
# preflight in `.github/workflows/apply-web-platform-infra.yml`, which reads INNGEST_CUTOVER_FLIP before a
# host replace (#8252). Until this token existed that read rode on DOPPLER_TOKEN_INNGEST_ARM, a read/write
# token (inngest-arm-write-token.tf), and silently degraded to "SKIPPED" the moment the arm token was gone.
# The preflight now FAILS CLOSED without this token, so the arm token's revoke no longer disables the guard.
#
# NOT the same thing as doppler_service_token.inngest_flip (inngest-host.tf): that one is the ON-HOST
# read/WRITE flip credential, written to /etc/default/inngest-flip and consumed only by
# inngest-cutover-flip.service; it is never published to a github_actions_secret.
#
# What `access = "read"` buys and does not buy. It bounds WRITES. It does not narrow READS: a Doppler token
# is scoped to a config, not to a key, so this token can read every secret in soleur-inngest/prd
# (INNGEST_REDIS_LUKS_KEY, INNGEST_TLS_KEY, INNGEST_SIGNING_KEY, INNGEST_EVENT_KEY and the rest). It is a
# repo-level secret, so it resolves in any workflow on any pushed branch with no reviewer gate. After the arm
# token is eventually revoked this is the only repo-wide read path to those keys. The rotation owner is the
# repository owner, via the recipe below. Fetching the token inside the main-only `infra-privileged` job from
# a Tier-B secret (soleur-infra-privileged/prd, precedent GITHUB_APP_RUNTIME_DOPPLER_TOKEN) is the
# alternative, rejected for now because it needs a new privileged secret plus a loader change in a
# prod-mutating apply; moving it before the arm revoke is tracked in #12158. No expires_at, like the sibling
# tokens: an expiry would become a silent fail-closed outage of the preflight.
#
# By-reference project/config (not the soleur-inngest / prd string literals), as inngest_arm_write: this
# builds the dependency edge onto doppler_project.inngest and doppler_environment.inngest_prd. Both carry
# prevent_destroy = true, so a teardown of either first needs a reviewed lift of that guard. Once the arm
# token is gone this token is the only per-merge path onto those two parents, so a teardown removes BOTH
# -target lines for this file's resources from the default allow-list first.
#
# Repo-scoped secret, not an environment secret: the Terraform GitHub App cannot write environment secrets
# (the arm token's file records the 403). Residual exposure is the one stated above.
#
# Rotation: `terraform apply -replace=doppler_service_token.inngest_flip_read
# -target=doppler_service_token.inngest_flip_read -target=github_actions_secret.doppler_token_inngest_flip_read`.
# `-target` selects dependencies, never dependents, so BOTH targets are required for the new key to reach the
# secret in the same apply. Never `-replace` on a PARTIAL apply: that orphans a live key. State holds `.key`
# (Computed + Sensitive) in the R2-backed encrypted tfstate and it cannot be re-read from Doppler; state-loss
# recovery is `-replace` plus revoking the orphan by slug. Repair for a dead or missing token is in the
# runbook inngest-server.md, inherited-done section.
#
# autonomy-considered: provider-mint-applied (App auth + doppler_service_token + github repo secret).

resource "doppler_service_token" "inngest_flip_read" {
  project = doppler_project.inngest.name         # by-reference (builds the dep edge; NOT a bare string literal)
  config  = doppler_environment.inngest_prd.slug # by-reference (NOT "prd")
  name    = "inngest-ci-flip-read"               # distinct from inngest-boot, inngest-cutover-arm and the on-host inngest-flip
  access  = "read"
}

# No lifecycle.ignore_changes: a `-replace` rotation of the token must propagate the new key here in the
# same apply (do NOT add ignore_changes = [plaintext_value]).
resource "github_actions_secret" "doppler_token_inngest_flip_read" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_INNGEST_FLIP_READ"
  plaintext_value = doppler_service_token.inngest_flip_read.key
}
