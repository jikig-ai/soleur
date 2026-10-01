# Tasks: fix main-health-monitor step budgets and failure classifier (#8112)

<!-- markdownlint-disable MD038 -->

Plan: `knowledge-base/project/plans/2026-10-01-fix-main-health-monitor-step-budgets-and-failure-classifier-plan.md`

## Phase 1: RED first (tests before the workflow edit)

- [ ] 1.1 In `plugins/soleur/test/main-health-monitor-workflow.test.sh`, keep assertion (8) and add (8g): verdict greps carry `^RED `, `^UNACCOUNTED ` and the breakdown regex with `[1-9][0-9]* failed`; breakdown shape derived from `scripts/test-all.sh`
- [ ] 1.2 Extend `run_filer` with a second-capture argument and an `INFRA_OUTCOME` parameter
- [ ] 1.3 Add fixtures: `fx-controls-zero-failed`, `fx-fail-no-breakdown`, `fx-fail-corroborated`, `fx-red-only`, `fx-infra-killed`, and the two-capture case
- [ ] 1.4 Add the leak row (anchored `^SOLEUR| `, tail exactly once, no empty `--- (tail) ---` label) on the failing and killed arms
- [ ] 1.5 Add the arm-4 actions assertion (no revert instruction; says no suite verdict was produced)
- [ ] 1.6 Add the annotation assertion (`tests_elapsed_s`, `infra_elapsed_s`)
- [ ] 1.7 Add the Sentry parity guard (Guard 2): comment-stripped TF, block keyed on `name = "main-health-monitor"`, exactly one block, `MHM_SENTRY_TF` override
- [ ] 1.8 Raise the anti-vacuity floor (count rows x 2 shell arms); record the new number
- [ ] 1.9 Run the suite and record the new rows failing before Phase 2

## Phase 2: Classifier, tail and annotation

- [ ] 2.1 Demote `^\[FAIL\]` to display; verdict = `^RED |^UNACCOUNTED ` or breakdown with `[1-9][0-9]* failed`; label unconfirmed `[FAIL]`-shaped lines
- [ ] 2.2 Delete the raw `$(tail -30 "$file")` append and the orphaned `--- (tail) ---` header after the killed hits
- [ ] 2.3 Add arm-4 `ACTIONS` (main unverified, read the step list and compare elapsed with ceiling, do not revert on this alone)
- [ ] 2.4 Write per-step elapsed seconds to `$GITHUB_OUTPUT` after `rc=${PIPESTATUS[0]}`; print them in the `SOLEUR_MAIN_HEALTH` annotation
- [ ] 2.5 Add the fifth defect entry to the workflow header; re-run the suite GREEN

## Phase 3: Budgets and Sentry envelope

- [ ] 3.1 Measurement commit (workflow only): tests step 90 min, job `90 + infra + 15`; check no run is in flight or queued; dispatch once with `dry_run=true` on the branch; arm a Monitor watch
- [ ] 3.2 Read `tests_elapsed_s` from the check-run annotation; confirm the runner printed its breakdown; cross-check against the 54 and 60 minute bounds
- [ ] 3.3 Derive `tests_step = max(30, roundup5(1.5 * T_max))`, `job = tests + infra + 15`; update the TIMEOUT BUDGET comment (run id, arithmetic, branch-shape bias)
- [ ] 3.4 Final commit (separate): derived ceilings, plus `max_runtime_minutes = job`, `checkin_margin_minutes = job + 25` and corrected comments in `apps/web-platform/infra/sentry/cron-monitors.tf`
- [ ] 3.5 Infra ceiling: only if PR #9383 merged and an undisturbed figure exists; otherwise leave and file the conditional follow-up (blocked-by #9383)

## Phase 4: Verification and ship

- [ ] 4.1 Run the monitor test, `scripts/lint-diagnosis-claims.sh`, `scripts/lint-guard-contract.py`, `scripts/lint-infra-no-human-steps.py --changed --base origin/main`, and the sentry-monitor-iac-parity vitest suite
- [ ] 4.2 Confirm the diff touches no git-data or apt-bounded path
- [ ] 4.3 Post a corrective comment on #8112 before merge
- [ ] 4.4 PR body: `Closes #8112`, Changelog, residual-infra note, the new anti-vacuity floor number
- [ ] 4.5 Post-merge: `apply-sentry-infra.yml` success; `apply-web-platform-infra.yml` plans no change; non-dry-run dispatch reads `tests=success`; reopen #8112 with evidence if not
