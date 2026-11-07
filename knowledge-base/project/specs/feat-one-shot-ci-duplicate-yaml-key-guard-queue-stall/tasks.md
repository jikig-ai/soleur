# Tasks: strict duplicate-key guard + stall-cause naming (Ref #9927, Ref #12283)

Plan: `knowledge-base/project/plans/2026-11-07-ci-strict-duplicate-key-guard-and-queue-stall-cause-plan.md`
Never touch: `scripts/test-all.sh`, `ci.yml`, `apps/web-platform/infra/**`, `CI_ORACLE_LANE`, the SOLEUR-DEBT marker near ci.yml:2220, #12275.

## Phase 1: RED tests first
- 1.1 Create `.github/scripts/test/test-check-workflow-duplicate-keys.sh` (battery B1-B12, mutation rows M1-M7, 3 control rows, exact pass floor); confirm RED because the guard is missing.
- 1.2 Extend `plugins/soleur/test/merge-queue-stall-check.test.sh`: `gh api -X GET repos/.../actions/runs` stub arm that applies `event`, `created`, pagination; rows L1-L14, mutation rows 1-11; pin `actions: read` in S4/M8; re-derive `EXPECTED_PASSES` from a green run.
- 1.3 Confirm both RED for the named reason.

## Phase 2: guard and member step
- 2.1 Write `.github/scripts/check-workflow-duplicate-keys.py` (compose-based walker, collect all, exit 0/1/2, `.yml`+`.yaml`, workflows + recursive actions).
- 2.2 Add step `workflow-duplicate-keys` (+ `member workflow-yaml-strict` aggregate row) to `.github/workflows/pr-quality-guards.yml`; update header comment.
- 2.3 `MIN_SUITES` 17 to 18 in `.github/scripts/test/run-all.sh` with floor-history line.
- 2.4 `scripts/required-checks.txt` disposition comment; ADR-032 dated addendum.
- 2.5 Run new suite, `lint-umbrella-aggregate.sh`, `run-all.sh`; guard on real tree prints `workflow-duplicate-keys=OK files=<N>`.

## Phase 3: stall-cause naming
- 3.1 Implement `queue_candidate_cause` in `.github/workflows/merge-queue-stall-check.yml` (enqueuedAt 5th TSV field, latest temp ref, `name == path`, `workflow_id` join, fail-soft, title suffix, body paragraph, `actions: read`, header + inline evidence comment).
- 3.2 Suite green; `scripts/lint-workflows.sh`, `lint-workflow-issue-write-scope.py`.
- 3.3 Read-only live replay for PR 12275 and 12279 (expected: 12275 names ci.yml; 12279 latest ref names nothing); save output for the PR body.

## Phase 4: gates
- 4.1 `lint-orphan-test-suites.sh`, `lint-guard-contract.py`, markdown lint; if `scripts/lib/` is forced, state it in the PR body.
- 4.2 `git diff --name-only origin/main...HEAD` shows none of the never-touch paths.

## Phase 5: ship
- 5.1 PR body: `Ref #9927`, `Ref #12283` (no closing keyword), RV-Q2 statement, run kind + leg for every CI claim, gate override note for any bot stall issue.
- 5.2 After every merge from main run the guard (ci.yml re-parse); bare `gh pr merge`; Monitor for waits.
- 5.3 File the `headCommit` deferral issue.
- 5.4 Post-merge: merge_group log evidence (`PASS  workflow-yaml-strict`), stall-check workflow_dispatch run, classify merge on #9927 via `git diff --name-only <prev-tip>..<new-tip>`, tick #12283 boxes with cited evidence only; close nothing.
