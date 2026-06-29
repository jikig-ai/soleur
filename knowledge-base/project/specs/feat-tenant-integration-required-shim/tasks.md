---
feature: tenant-integration-required-shim
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-29-feat-tenant-integration-required-check-shim-plan.md
issue: 5585
---

# Tasks: tenant-integration required-check shim

## Phase 0 — Confirm edit set (read-only)

- [ ] 0.1 Confirm `test-destroy-guard-counter.sh` is delete-only (no count-of-14 assertion) + `create/update-ci-required-ruleset.sh` are frozen one-shots → all no-edit.
- [ ] 0.2 Confirm `CHECK_NAMES` in `bot-pr-with-synthetic-checks/action.yml` is hardcoded + the completeness lint exempts composite-action consumers (→ action needs its own grep gate).
- [ ] 0.3 Read ADR-032 `## Decision` + `## Sharp Edges`; enumerate the `14` doc sites.

## Phase 1 — Workflow shim

- [ ] 1.1 Remove `on.push.paths` + `on.pull_request.paths` from `tenant-integration.yml` (keep branches + workflow_dispatch).
- [ ] 1.2 Add `detect-changes` job (mirror `ci.yml:40-69`); anchors = former paths PLUS the workflow file itself (supersedes spec TR4); non-PR → `tenant=true`; `$BASE_REF` via quoted env.
- [ ] 1.3 Gate heavy `tenant-integration` job: `needs: detect-changes`, `if: needs.detect-changes.outputs.tenant == 'true'`.
- [ ] 1.4 Add `tenant-integration-required` job (`if: always()`, `needs: [detect-changes, tenant-integration]`, in-`run:` allow-list assertion: pass iff `detect-changes.result==success` AND `tenant-integration.result ∈ {success,skipped}`; else fail).
- [ ] 1.5 Keep `concurrency.cancel-in-progress: false` (no change).
- [ ] 1.6 Harden `detect-changes`: `set -uo pipefail`; git/checkout error or missing `origin/$BASE_REF` → fail the job (never silent `tenant=false`).

## Phase 2 — IaC registration + count sites

- [ ] 2.1 Add `required_check` block for `tenant-integration-required` to `infra/github/ruleset-ci-required.tf`; update its header comment `14`→`15`.
- [ ] 2.2 Add `tenant-integration-required` to `scripts/required-checks.txt` AND `scripts/ci-required-ruleset-canonical-required-status-checks.json`.
- [ ] 2.3 `terraform fmt && terraform validate` in `infra/github` (no apply/plan — needs prd creds).

## Phase 3 — Bot-synthetic

- [ ] 3.1 Add `tenant-integration-required` to `CHECK_NAMES` in `bot-pr-with-synthetic-checks/action.yml`.
- [ ] 3.2 Run `scripts/lint-bot-synthetic-completeness.sh`; fix any flagged raw-`gh-pr-create` workflow; paste audit list into PR body. (`post-bot-statuses.sh` = Statuses API, not ruleset-satisfying → no edit unless a live consumer needs it.)

## Phase 4 — ADR

- [ ] 4.1 Amend ADR-032: count sites `14`→`15` + always-run-gate-job pattern for path-filtered required checks (job-name-contract sharp edge).

## Phase 5 — Verification (pre-merge)

- [ ] 5.1 `bash scripts/test-all.sh` green.
- [ ] 5.2 `actionlint` + `bash -c` on extracted `run:` snippets.
- [ ] 5.3 `terraform fmt -check` + `terraform validate` green; `grep -c '^      required_check {' infra/github/ruleset-ci-required.tf` → 15; direct grep of the 3 synthetic/registration sources.

## Post-merge (operator — automated)

- [ ] P.1 Confirm `apply-github-infra.yml` run is green; live ruleset lists `tenant-integration-required`.
- [ ] P.2 Confirm first unrelated PR reports the gate green with heavy job skipped.
