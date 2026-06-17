# Learning: the workflow `-target=` allow-list has a CI parity guard, but it covers ONLY `terraform_data.*` and is one-directional

## Problem

PR #5478 added two `-target=` lines (`random_password.inngest_redis_password_prd`,
`doppler_secret.inngest_redis_password_prd`) to the terraform-plan allow-list in
`.github/workflows/apply-web-platform-infra.yml`. The plan (and the issue body) asserted
"no test asserts the workflow `-target=` list count/membership", reasoning only about the
destroy-guard suites (`tests/scripts/test-destroy-guard-counter-web-platform.sh`,
`test-destroy-guard-regex-parity.sh`) and `apps/web-platform/infra/inngest.test.sh`.

That blanket claim is imprecise. `plugins/soleur/test/terraform-target-parity.test.ts` **does**
parse the workflow's `-target=` set — but its `collectSshProvisioned` walk and regex
(`/-target=terraform_data\.(...)/`) only cover the `terraform_data.*` subset (the SSH-provisioned
resources). `random_password` / `doppler_secret` / `random_id` targets are invisible to it.

## Solution / Key Insight

The change was genuinely unaffected (the parity test can't break on non-`terraform_data` targets,
and it stayed green: 12 pass / 0 fail). But two facts are worth carrying forward for the next PR
that touches this allow-list:

1. **There IS a parity guard on the workflow `-target=` list, scoped to `terraform_data.*` only.**
   A plan that needs to reason about "will my new target break/trip a test?" should name
   `terraform-target-parity.test.ts` explicitly and state whether the new target is a
   `terraform_data` resource (guarded) or not (unguarded).
2. **The parity guard is one-directional.** It checks that every `terraform_data` resource with an
   SSH provisioner has a matching `-target=`; it does NOT catch a stale/typo'd `-target=` that
   matches no resource. Terraform exits 0 on a no-match `-target`, so a misspelled
   `random_password`/`doppler_secret`/`random_id` target silently no-ops with no CI signal. Spell
   such targets against `inngest.tf` (or the owning `.tf`) by hand at /work time — there is no
   net to catch it.

Not filed as an issue: widening the parity test to all target classes + bidirectional is a
>30-line change in a different subsystem with low payoff (a no-op typo is self-evident on the
first apply run's plan output), and net-issue-flow discipline says don't grow the backlog for it.

## Session Errors

1. **IaC Routing Gate (plan Phase 2.8) false-fired on quoted runbook prose.** The gate matched a
   `doppler secrets set INNGEST_CUTOVER_QUIESCE=...` substring quoted verbatim from the existing
   (#5459-shipped) runbook steps. **Recovery:** added the `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`
   opt-out — the Step-0 apply IS routed through Terraform and the quoted lines are pre-existing
   runtime feature-flag toggles, not new manual provisioning. **Prevention:** the ack comment is the
   designed escape valve; one-off, no workflow change needed.
2. **Edit of `apply-web-platform-infra.yml` failed `File has not been read yet`.** I had grepped the
   file but not Read it before editing. **Recovery:** Read the target lines, re-applied. **Prevention:**
   already covered by `hr-always-read-a-file-before-editing-it`; grep is not a substitute for Read.
3. **Plan AC7 `git diff --stat main` listed unrelated #5477 files.** The local `main` ref lags
   origin/main in a bare-repo worktree. **Recovery:** re-diffed against `origin/main` (three-dot).
   **Prevention:** already documented in `work/SKILL.md` (the bare-repo stale-ref guard, #4587) — use
   `origin/main` for over-reach checks, never the local `main` ref.

## Tags
category: integration-issues
module: apps/web-platform/infra, .github/workflows
