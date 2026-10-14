# Tasks — fix(kb-drift): provision ingest secrets into app-runtime Doppler config `prd`

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

lane: cross-domain
plan: knowledge-base/project/plans/2026-05-29-fix-kb-drift-signing-key-app-runtime-plan.md

## Phase 1 — Terraform changes (infra-only, no app source)

- [ ] 1.1 In `apps/web-platform/infra/variables.tf`, add `variable "kb_drift_operator_founder_id"` — `type = string`, `sensitive = true`, with a `description`, NO `default` (fail-closed per `hr-tf-variable-no-operator-mint-default`). Match the style of the sibling sensitive vars (e.g., `cf_api_token_*`).
- [ ] 1.2 In `apps/web-platform/infra/kb-drift.tf`, append `doppler_secret.kb_drift_ingest_signing_key_app_runtime`: `project = "soleur"`, `config = "prd"`, `name = "KB_DRIFT_INGEST_SIGNING_KEY"`, `value = "kbdrift-${random_id.kb_drift_ingest_signing_key.hex}"`, `visibility = "masked"`, NO `lifecycle.ignore_changes`. Add the walker-signs / app-verifies comment (see plan Proposed Solution).
- [ ] 1.3 In `apps/web-platform/infra/kb-drift.tf`, append `doppler_secret.kb_drift_operator_founder_id_app_runtime`: `project = "soleur"`, `config = "prd"`, `name = "KB_DRIFT_OPERATOR_FOUNDER_ID"`, `value = var.kb_drift_operator_founder_id`, `visibility = "masked"`, NO `lifecycle.ignore_changes` (see Precedent-Diff for the founder-id divergence rationale).
- [ ] 1.4 Verify `random_id.kb_drift_ingest_signing_key` and the existing `doppler_secret.kb_drift_ingest_signing_key` (kb-drift.tf:35-46) are UNCHANGED (`git diff` shows no edit to those lines).

## Phase 2 — Validation (pre-merge)

- [ ] 2.1 `terraform validate` passes in `apps/web-platform/infra/` (run via the nested `doppler run` invocation from `variables.tf:1-13`; pass `-var="ssh_key_path=/tmp/ci_ssh_key.pub"` if `plan` errors on the missing var).
- [ ] 2.2 `terraform plan` against live state shows exactly `Plan: 2 to add, 0 to change, 0 to destroy`. Re-run immediately before publishing the apply runbook (drift-snapshot staleness). If it diverges, reconcile before merge.
- [ ] 2.3 PR body uses `Ref #<issue>` (NOT `Closes`); includes a `## Changelog` section; label `semver:patch`.

## Phase 3 — Apply + redeploy (post-merge, operator-local)

- [ ] 3.1 Set `KB_DRIFT_OPERATOR_FOUNDER_ID` (operator-founder Supabase `auth.users.id` UUID) in Doppler `prd_terraform` so `TF_VAR_kb_drift_operator_founder_id` resolves. (Human identity value — not derivable.)
- [ ] 3.2 Run `terraform apply` via the nested `doppler run` invocation (plan Apply Path) — creates both `prd` secrets.
- [ ] 3.3 Trigger an app redeploy so the container re-runs `ci-deploy.sh` and re-downloads `prd` (a TF-only diff does not trigger `web-platform-release.yml`). Prefer the existing release/deploy webhook path; fold into `/soleur:ship` post-merge verification.

## Phase 4 — Acceptance verification (post-merge)

- [ ] 4.1 Verify #1: bad-sig POST to `https://app.soleur.ai/api/internal/kb-drift-ingest` returns `401` (not 500, not 307). Command in plan AC.
- [ ] 4.2 Verify #2: `gh workflow run "KB-drift walker"`, then poll `gh run list --workflow="KB-drift walker" --limit 1 --json conclusion` until `conclusion == "success"`.
- [ ] 4.3 After both pass, `gh issue close <issue>` with a comment linking the apply + walker run.
