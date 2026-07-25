# Closes #6369. Read/write Doppler service token for the no-SSH `op=arm`
# (and the reverse `op=rollback` flip-write) in `.github/workflows/cutover-inngest.yml`.
# op=arm performs the three arm-flip writes on `soleur-inngest/prd`
# (INNGEST_POSTGRES_URI, INNGEST_HEARTBEAT_URL, then INNGEST_CUTOVER_FLIP=armed LAST)
# that were previously an out-of-band operator hand-off in op=execute's SEAM
# (cutover-inngest.yml:607-611). The two SOURCE values are read read-through from
# `soleur/prd_terraform` via the workflow's EXISTING read-only DOPPLER_TOKEN (CTO
# decision 2026-07-12 / ADR-100 Decision 6b — the prod DSN is already CI-readable there,
# SHA-identical to canonical prd; no operator seed). This token is ONLY for the WRITES to
# the isolated soleur-inngest project.
#
# Blast radius: `access = "read/write"` on `soleur-inngest/prd` ONLY. This project is
# ISOLATED — a separate Doppler root-config project (inngest-host.tf:78-85), with no
# config-inheritance path to `soleur/prd`. The write surface is the dedicated inngest host's boot creds +
# the cutover-flip FSM state. IMPORTANT: once op=arm has run, this token is also a STANDING
# READ handle to the ARMED PROD `INNGEST_POSTGRES_URI` it wrote into soleur-inngest/prd
# (a session-pooler DSN granting direct read/write to the inngest Postgres). It MUST be
# revoked post-cutover — see the runbook lifecycle step + Rotation below.
#
# Distinct from the host-boot token `doppler_service_token.inngest` ("inngest-boot"):
# different name ("inngest-cutover-arm") and consumer (CI vs the host cloud-init). Both are
# read/write on soleur-inngest/prd as of #6178 — the host-boot token gained write so the
# flip FSM can advance INNGEST_CUTOVER_FLIP on-host (inngest-cutover-flip.sh:flag_set) — so
# the tokens no longer differ by ACCESS, only by name+consumer. This is the FIRST CI-consumed
# read/write token into the isolated soleur-inngest project; the host-boot token is the
# host-consumed one. CI can now WRITE soleur-inngest/prd (ADR-100 Decision 6b).
#
# By-reference project/config (NOT the soleur-inngest / prd string literals): this builds
# the Terraform dependency edge onto doppler_project.inngest + doppler_environment.inngest_prd,
# matching the read token's by-reference wiring (inngest-host.tf:174-175). Consequence: the
# per-merge `-target` of this token is a STANDING transitive path onto the excluded project/env.
# A teardown/re-provision of doppler_project.inngest must be OPERATOR-applied FIRST — else the
# next per-merge CI apply recreates the isolated project unattended. (Precedent for the
# transitive-edge concern: doppler_service_token.inngest, by-reference; NOT
# doppler_service_token.write, which is a string-literal token with zero edges.)
#
# Rotation / revoke: `terraform apply -replace=doppler_service_token.inngest_arm_write` mints
# a new key AND (because this file deliberately omits `lifecycle.ignore_changes =
# [plaintext_value]` on the env secret below) propagates it to the consumer in the SAME apply.
# The old key is orphaned but still valid — revoke it via `doppler configs tokens revoke`.
# Post-cutover, `-replace` + revoke is the mechanism that closes the standing-read-handle
# blast radius (runbook § Cutover — post-cutover token revoke).
#
# State storage: `.key` is Computed + Sensitive per the Doppler provider; the value lands in
# the R2-backed encrypted `terraform.tfstate` on create and CANNOT be re-read from the Doppler
# API (same posture as doppler_service_token.write / .inngest / .registry). State-loss recovery
# is `-replace` (mints a new token, orphans the old one — revoke manually).
#
# Human ack (D5/C4): a workflow_dispatch alone is only repo `actions:write` — weaker than the
# Doppler-console credentials the manual arm-write required. The `inngest-cutover` GitHub
# Environment (below) carries a REQUIRED-REVIEWER protection rule, and the op=arm / op=rollback
# jobs declare `environment: inngest-cutover`, so the run is held in "Waiting" for reviewer
# approval BEFORE any step executes — that approval IS the human ack. (The token itself is a
# repo-level github_actions_secret, not an environment secret, because the TF App cannot write
# environment secrets — see the resource comment below; the reviewer gate lives on the JOB, so
# the ack holds regardless.) There is no interactive pre-write value confirmation, by design
# (AC-NOBODY forbids echoing the values).
#
# autonomy-considered: provider-mint-applied (App auth + doppler_service_token + github repo secret).

resource "doppler_service_token" "inngest_arm_write" {
  project = doppler_project.inngest.name         # by-reference (builds the dep edge; NOT a bare string literal)
  config  = doppler_environment.inngest_prd.slug # by-reference (NOT "prd")
  name    = "inngest-cutover-arm"                # distinct from the read token "inngest-boot"
  access  = "read/write"
}

# GitHub Environment with a required-reviewer protection rule (D5/C4). The op=arm and
# op=rollback jobs gate on `environment: inngest-cutover`; the reviewer (the operator) must
# approve each dispatch before the environment secret below resolves. reviewers.users takes
# numeric GitHub user IDs — 54279 = @deruelle (the operator/founder).
resource "github_repository_environment" "inngest_cutover" {
  repository  = "soleur"
  environment = "inngest-cutover"

  reviewers {
    users = [54279]
  }
}

# The write token published as a REPO-level github_actions_secret. It was originally an ENVIRONMENT
# secret (github_actions_environment_secret) so it would resolve ONLY in a job that passed the
# inngest-cutover reviewer gate — but the TF GitHub App lacks permission to write ENVIRONMENT
# secrets: the first apply failed 403 "Resource not accessible by integration" on
# `environments/inngest-cutover/secrets/public-key`, while repo secrets (see
# `github_actions_secret.doppler_token_write`) DO apply cleanly under the same App. So the token is
# a repo secret and the required-reviewer HUMAN-ACK is preserved a DIFFERENT way: the op=arm /
# op=rollback JOB declares `environment: inngest-cutover` (the github_repository_environment above),
# which holds the run in "Waiting" for reviewer approval BEFORE any step executes — independent of
# where the secret lives. Residual exposure: the token is readable by every workflow (the same
# exposure class as doppler_token_write, an equally read/write Doppler token), bounded by the
# conditional injection (`inputs.op == 'arm' && secrets.DOPPLER_TOKEN_INNGEST_ARM || ''`) and the
# post-cutover revoke. Upgrade back to an environment secret if the App is later granted
# environment-secret write. NO lifecycle.ignore_changes → a `-replace` rotation of the token
# propagates the new key here in the same apply (do NOT add ignore_changes = [plaintext_value]).
resource "github_actions_secret" "doppler_token_inngest_arm" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_INNGEST_ARM"
  plaintext_value = doppler_service_token.inngest_arm_write.key
}
