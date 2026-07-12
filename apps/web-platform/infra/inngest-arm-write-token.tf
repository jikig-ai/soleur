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
# Distinct from the READ-only host-boot token `doppler_service_token.inngest`
# ("inngest-boot", inngest-host.tf:173-178): different name ("inngest-cutover-arm"),
# access (read/write vs read), and consumer (CI vs the host cloud-init). This is the FIRST
# CI-consumed read/write token into the isolated soleur-inngest project — prior tokens there
# are read-only host-boot. CI can now WRITE soleur-inngest/prd (ADR-100 Decision 6b).
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
# Human ack (D5/C4): unlike doppler_service_token.write (a repo-wide github_actions_secret
# readable by every workflow), this key is published as a GitHub ENVIRONMENT secret under the
# `inngest-cutover` environment with a REQUIRED-REVIEWER protection rule. A workflow_dispatch is
# only repo `actions:write` — weaker than the Doppler-console credentials the manual arm-write
# required; the environment's required-reviewer gate restores that human ack. The op=arm /
# op=rollback jobs declare `environment: inngest-cutover`, so the reviewer must approve the
# dispatch before the token resolves. The dispatch + environment approval IS the ack; there is
# no interactive pre-write value confirmation, by design (AC-NOBODY forbids echoing the values).
#
# autonomy-considered: provider-mint-applied (App auth + doppler_service_token + github env secret).

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

# The write token published as an ENVIRONMENT secret (NOT a repo-wide github_actions_secret —
# that would be readable by every workflow, defeating the required-reviewer scoping). Resolvable
# ONLY to a job that declares `environment: inngest-cutover` and passed the reviewer gate.
# NO lifecycle.ignore_changes → a `-replace` rotation of the token propagates the new key here in
# the same apply (do NOT add ignore_changes = [plaintext_value]: it would strand the secret on
# the old, soon-revoked key).
resource "github_actions_environment_secret" "doppler_token_inngest_arm" {
  repository      = "soleur"
  environment     = github_repository_environment.inngest_cutover.environment
  secret_name     = "DOPPLER_TOKEN_INNGEST_ARM"
  plaintext_value = doppler_service_token.inngest_arm_write.key
}
