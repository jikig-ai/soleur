# Closes #6369. Read/write Doppler service token for the no-SSH cutover-flip writes in
# `.github/workflows/cutover-inngest.yml`. As of #9927 item 8 the verbs that consume it are
# `op=rollback` and `op=resume` ONLY: `op=arm`, `op=reflush` and `op=luks-cutover` were retired
# (their flags are terminal `done`) and the inherited-done preflight moved to the read-only
# DOPPLER_TOKEN_INNGEST_FLIP_READ (inngest-flip-read-token.tf). The paragraphs below describe the
# original design; where they name a retired verb, read it as history.
# op=arm (retired) performed the three arm-flip writes on `soleur-inngest/prd`
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
# next per-merge CI apply recreates the isolated project unattended. It now ALSO needs a reviewed
# lift of its prevent_destroy first (runbook "Sole-copy protection and key loss", #9879). (Precedent for the
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
# Environment (below) carries a REQUIRED-REVIEWER protection rule, and the op=rollback / op=resume
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

# GitHub Environment with a required-reviewer protection rule (D5/C4). The op=rollback and
# op=resume jobs gate on `environment: inngest-cutover`; the reviewer (the operator) must
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
  # environment (later converted into `inngest_backstop_retire` by #8285, which sourced its gate the
  # same way, and deleted by #8285 PR B once the backstop volume was destroyed) sourced BOTH of its
  # guards from `${GITHUB_WORKSPACE}` — so without a branch pin,
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
# a repo secret and the required-reviewer HUMAN-ACK is preserved a DIFFERENT way: the op=rollback /
# op=resume JOB declares `environment: inngest-cutover` (the github_repository_environment above),
# which holds the run in "Waiting" for reviewer approval BEFORE any step executes — independent of
# where the secret lives. Residual exposure: the token is readable by every workflow (the same
# exposure class as doppler_token_write, an equally read/write Doppler token).
#
# CONSUMERS — keep this list current; the bound stated here is only as true as the list.
#   1. cutover-inngest.yml — conditional injection for `op == 'rollback' || 'resume'` ONLY (#9927
#      item 8 retired arm, reflush and luks-cutover), and those jobs declare
#      `environment: inngest-cutover`, so they hold for the reviewer. These two are the live
#      break-glass verbs once INNGEST_CUTOVER_FLIP is `done`, which is why this token is not yet
#      revocable: a replacement write-credential design is tracked on the #9927 follow-up.
#   2. (RETIRED by #8285 PR B) apply-web-platform-infra.yml, job `inngest_backstop_retire` (converted
#      from `inngest_volume_recut` by #8285) — unconditional injection, but that job declared
#      `environment: inngest-cutover`, so the human ack gated it. The job no longer exists; the item
#      keeps its number so the references below stay valid.
#   3. (RETIRED by #9927 item 8) apply-web-platform-infra.yml, job `inngest_host_replace`, the #7228
#      inherited-`done` preflight. It now reads INNGEST_CUTOVER_FLIP with the read-only
#      DOPPLER_TOKEN_INNGEST_FLIP_READ (inngest-flip-read-token.tf) and FAILS CLOSED without it, so
#      revoking this token no longer disables that guard. The earlier amendments to this item (the
#      2026-09-17 addition and the 2026-09-23 #8209 / ADR-241 D2 note that the job declares
#      `environment: infra-privileged`) are superseded by the retirement.
#
# The remaining residual is consumer 1: a read/WRITE credential on the whole soleur-inngest/prd config
# that is readable by every workflow, bounded by the reviewer gate on the two verbs that use it.
# RE-EVAL TRIGGER: a replacement write-credential design for rollback/resume, after which this token
# is revoked by its owner (not by CI).
#
# NOT THE SAME THING as doppler_service_token.inngest_flip (inngest-host.tf), whose name now sits
# close to FLIP_READ in the eye: that one is the ON-HOST read/WRITE flip credential, written to
# /etc/default/inngest-flip and consumed as an EnvironmentFile only by inngest-cutover-flip.service, and it is NEVER published
# to a github_actions_secret. DOPPLER_TOKEN_INNGEST_FLIP_READ is the CI-side READ token that replaced
# this token for the preflight (former consumer 3).
#
# Upgrade back to an environment secret if the App is later granted
# environment-secret write. NO lifecycle.ignore_changes → a `-replace` rotation of the token
# propagates the new key here in the same apply (do NOT add ignore_changes = [plaintext_value]).
resource "github_actions_secret" "doppler_token_inngest_arm" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_INNGEST_ARM"
  plaintext_value = doppler_service_token.inngest_arm_write.key
}

# =============================================================================
# #9927 step D2-2 / #12158 — the REPLACEMENT write token for op=rollback and op=resume
# (design arm-token-replacement-design-12158.md; CTO rulings D1, D1b, D1c of 2026-11-06).
# Same blast radius as the arm token above — read/write on the isolated soleur-inngest/prd
# config, project and config BY REFERENCE so it builds the same dependency edge. The name is
# distinct from "inngest-cutover-arm" per D1c. The gain over the arm token is DELIVERY ONLY:
# this key is never published as a github_actions_secret (the TF App still cannot write
# environment secrets — the 403 recorded above stands), so it surfaces ONLY as the sensitive
# output below, and the staged relay script
# knowledge-base/project/specs/feat-one-shot-9927-d2-2-new-write-path/relay-inngest-write-token.sh
# copies it over stdin into the `inngest-cutover` GitHub ENVIRONMENT secret
# DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE — a main-only, required-reviewer-gated environment. The
# rollback and resume ops consume that environment secret (cutover-inngest.yml), narrowing
# delivery from a repo secret resolvable on any pushed branch to a gated environment secret.
#
# The arm token above is NOT touched: it stays the live credential until the #12158 step-4
# revoke change removes it, its secret, their two -target lines and the export step (the
# owner-gated destroy then applies). This file is never deleted whole — it also defines the
# inngest_cutover environment that still gates op=backup, rollback and resume.
#
# Rotation / staleness: `terraform apply -replace=doppler_service_token.inngest_cutover_write`
# mints a new key and LEAVES THE ENVIRONMENT SECRET STALE — after a -replace, re-run the relay
# script before re-dispatching op=rollback or op=resume. The workflow's write-token freshness
# check refuses with verdict=write_token_stale until then (fail closed; the runbook records
# the order: replace, then re-run the relay). Revoke of THIS token: remove this resource, its
# -target line in apply-web-platform-infra.yml, the credential step in cutover-inngest.yml and
# the census name, then an owner-gated destroy (or `doppler configs tokens revoke`) plus
# `gh secret delete DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE --env inngest-cutover` — record date
# and evidence on #12158. Revisit coverage: follow-through tracker #12738 and
# scripts/followthroughs/inngest-write-token-revisit-12738.sh (the arm-token probe keeps
# watching only the arm token).
resource "doppler_service_token" "inngest_cutover_write" {
  project = doppler_project.inngest.name         # by-reference (same dep edge as the arm token)
  config  = doppler_environment.inngest_prd.slug # by-reference (NOT "prd")
  name    = "inngest-cutover-write"              # distinct from "inngest-cutover-arm"
  access  = "read/write"
}

# Read ONLY by the staged relay script via `terraform output -raw inngest_cutover_write_token`.
# sensitive = true keeps the key out of every plan/apply log line; the value lands in the
# R2-backed encrypted terraform.tfstate like the arm token's .key (same posture — D1c records
# that keeping this key out of state buys nothing while the sibling keys are already there).
output "inngest_cutover_write_token" {
  value     = doppler_service_token.inngest_cutover_write.key
  sensitive = true
}
