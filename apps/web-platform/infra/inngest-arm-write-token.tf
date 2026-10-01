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

  # #7695. THE REVIEWER RULE ALONE DOES NOT GATE THE CODE THAT RUNS. `workflow_dispatch` executes
  # the SELECTED REF's workflow and the scripts that workflow sources, and the reviewer prompt
  # shows a branch NAME, not a diff. The destructive `inngest_volume_recut` job added under this
  # environment sources BOTH of its guards from `${GITHUB_WORKSPACE}` — so without a branch pin,
  # anyone who can dispatch can point the run at a branch carrying neutered guards and ask the
  # reviewer to approve what reads as a routine recut.
  #
  # Measured 2026-09-03: `gh api repos/jikig-ai/soleur/environments/inngest-cutover` returned
  # `deployment_branch_policy: null`, which the API reads as "every branch may deploy".
  # web-host-birth-environment.tf already carries the full argument for why that is fatal for a
  # gate sourced from the workspace, and already records THIS environment as one of three with a
  # null policy — it was written as a warning about a sibling and is now a defect in the sibling.
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# `custom_branch_policies = true` only declares that the environment uses a NAMED LIST; without
# this resource the list is empty, which GitHub treats as "no branch may deploy" — the opposite
# failure from omitting the block, and equally wrong. Both halves are required.
resource "github_repository_environment_deployment_policy" "inngest_cutover_main" {
  repository     = "soleur"
  environment    = github_repository_environment.inngest_cutover.environment
  branch_pattern = "main"
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
# exposure class as doppler_token_write, an equally read/write Doppler token).
#
# CONSUMERS — keep this list current; the bound stated here is only as true as the list.
#   1. cutover-inngest.yml:123 — conditional injection
#      (`(op == 'arm' || 'rollback' || 'resume') && secrets.… || ''`), and those jobs declare
#      `environment: inngest-cutover` (cutover-inngest.yml:78), so they hold for the reviewer.
#   2. apply-web-platform-infra.yml, job `inngest_volume_recut` — unconditional injection, but
#      that job declares `environment: inngest-cutover`, so the human ack still gates it.
#   3. apply-web-platform-infra.yml, job `inngest_host_replace`, the #7228 inherited-`done`
#      preflight (added 2026-09-17) — UNCONDITIONAL injection. Still the FIRST resolution site
#      with neither of the two bounds above, and still the residual this comment is about.
#      AMENDED 2026-09-23 (#8209, ADR-241 D2): the "job with NO `environment:` key" clause is
#      no longer true — that job now declares `environment: infra-privileged`. That is NOT a
#      third bound: the environment has no reviewers by design, so nothing human gates it. What
#      it adds is branch reach — the deployment-branch policy admits `main` only, so the
#      injection is unreachable from a dispatch on any other ref.
#
# An earlier revision of this comment asserted the residual was "bounded by the conditional
# injection … and the post-cutover revoke". Consumer 3 falsifies the first half, and this file
# is not in that PR's diff, which is exactly why the claim went unre-read. Corrected rather than
# left standing: a comment that overstates a control teaches the next reader the wrong bound.
#
# What consumer 3 actually needs is ONE read of ONE key. What it carries is read/WRITE on the
# whole soleur-inngest/prd config. The proportionate fix is a second, `access = "read"` service
# token (`doppler_service_token` supports it) published as DOPPLER_TOKEN_INNGEST_FLIP_READ and
# consumed there instead — which also survives the post-cutover revoke below, where consumer 3
# otherwise degrades silently and permanently into its "read failed" branch. Tracked as a
# follow-up because minting and publishing a new service token is a provisioning change with its
# own apply, not a review edit. RE-EVAL TRIGGER: whichever comes first — the post-cutover revoke
# of this token, or a FOURTH consumer being added.
#
# Upgrade back to an environment secret if the App is later granted
# environment-secret write. NO lifecycle.ignore_changes → a `-replace` rotation of the token
# propagates the new key here in the same apply (do NOT add ignore_changes = [plaintext_value]).
resource "github_actions_secret" "doppler_token_inngest_arm" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_INNGEST_ARM"
  plaintext_value = doppler_service_token.inngest_arm_write.key
}
