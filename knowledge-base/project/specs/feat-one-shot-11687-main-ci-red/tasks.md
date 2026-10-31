# Tasks: feat-one-shot-11687-main-ci-red (#11687)

Plan: knowledge-base/project/plans/2026-10-31-fix-main-ci-red-cf-lb-overlay-trio-plan.md

## Phase 1 — Baseline

- [x] 1.1 Confirm the three red gates on this branch: `bun test plugins/soleur/test/workflow-file-size.test.ts`, `bun test plugins/soleur/test/terraform-target-parity.test.ts`, `bash tests/scripts/test-infra-privileged-tier-census.sh` (expect the three documented signatures).

## Phase 2 — Signature 1: byte gate (apply-web-platform-infra.yml + runbook)

- [x] 2.1 Append `## push-paths sub-root exclusions` to `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` carrying the relocated prose (#7025/R10 NEGATED-not-paths-ignore mechanism note; per-root reasons for rung2-rehearsal, inngest-provision-rehearsal, git-data-root-key, lb-staging; the deliberate non-exclusions `modules/git-data-userdata/`, `cloud-init-inngest.yml`, `git-data-root-key.fingerprint`).
- [x] 2.2 In `.github/workflows/apply-web-platform-infra.yml` `push.paths:` (~lines 20–47), delete the four per-exclusion comment blocks; insert the 2-line context comment + `# Rationale: knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md §push-paths sub-root exclusions` pointer; keep all four `!` lines and the destroy-guard-filter entry verbatim.
- [x] 2.3 Verify `wc -c .github/workflows/apply-web-platform-infra.yml` ≤ 490000 (expect ~488.8 KB; if < 229 B saved, relocate additional sibling comment prose under the same heading).

## Phase 3 — Signature 2: ga_overlay redaction (cf-lb-overlay.yml)

- [x] 3.1 In `Terraform plan (GA LB trio only)`: add the shellcheck comment + `source "${GITHUB_WORKSPACE}/tests/scripts/lib/tf-redact-random-ids.sh"` near the run-block top; append `2>&1 | tf_redact_random_ids` to the `doppler run -- terraform plan` invocation; change `rc=$?` to `rc=${PIPESTATUS[0]}` (keep `set +e` and the `::error::` arm).
- [x] 3.2 In `Terraform apply (the graded tfplan)`: add the same source lines; append `2>&1 | tf_redact_random_ids` to the apply invocation (pipefail already preserves failure).
- [x] 3.3 Do NOT touch the staging arms (clean root), the `terraform show` plan-gate step, or `env.REHEARSAL_DIR` naming.

## Phase 4 — Signature 3: G4c root-list parity (test-infra-privileged-tier-census.sh)

- [x] 4.1 In `materialize_base_dir`: extend `mkdir -p` with `"$_dest/apps/web-platform/infra/lb-staging"`; extend `for _r in` to `apps/web-platform/infra apps/web-platform/infra/git-data-root-key apps/web-platform/infra/lb-staging` (lb-staging last).
- [x] 4.2 G4GIT fixture: `mkdir -p "$G4GIT/repo/apps/web-platform/infra/lb-staging"` and commit `apps/web-platform/infra/lb-staging/main.tf` (`resource "terraform_data" "base_lb" {}`) into M0 before the M0 commit, so all refs carry the root.
- [x] 4.3 Update the stale two-root doc comment at ~line 24.

## Phase 5 — Verify

- [x] 5.1 All three gates green per AC2–AC4; `grep -c 'tf_redact_random_ids' .github/workflows/cf-lb-overlay.yml` == 2.
- [x] 5.2 Adjacent suites green: `bash tests/scripts/test-cf-lb-overlay-gate.sh`; workflow lint clean on both edited workflows.
- [x] 5.3 PR body uses `Refs #11687` and summarizes all three fixes.
