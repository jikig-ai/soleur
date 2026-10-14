# Tasks: fix main-health-monitor step budgets and failure classifier (#8112)

<!-- markdownlint-disable MD038 -->

Plan: `knowledge-base/project/plans/2026-10-01-fix-main-health-monitor-step-budgets-and-failure-classifier-plan.md`

## Phase 1: RED first (tests before the workflow edit)

- [x] 1.1 In `plugins/soleur/test/main-health-monitor-workflow.test.sh`, keep assertion (8) and add (8g): verdict greps carry `^RED `, `^UNACCOUNTED ` and the breakdown regex with `[1-9][0-9]* failed`; breakdown shape derived from `scripts/test-all.sh`
- [x] 1.2 Extend `run_filer` with a second-capture argument and an `INFRA_OUTCOME` parameter
- [x] 1.3 Add fixtures: `fx-controls-zero-failed`, `fx-fail-no-breakdown`, `fx-fail-corroborated`, `fx-red-only`, `fx-infra-killed`, and the two-capture case
- [x] 1.4 Add the leak row (anchored `^SOLEUR| `, tail exactly once, no empty `--- (tail) ---` label) on the failing and killed arms
- [x] 1.5 Add the arm-4 actions assertion (no revert instruction; says no suite verdict was produced)
- [x] 1.6 Add the annotation assertion (`tests_elapsed_s`, `infra_elapsed_s`)
- [x] 1.7 Add the Sentry parity guard (Guard 2): comment-stripped TF, block keyed on `name = "main-health-monitor"`, exactly one block, `MHM_SENTRY_TF` override
- [x] 1.8 Raise the anti-vacuity floor (count rows x 2 shell arms); record the new number
- [x] 1.9 Run the suite and record the new rows failing before Phase 2

## Phase 2: Classifier, tail and annotation

- [x] 2.1 Separate display greps (`RED`/`UNACCOUNTED` first); show the `parent process gone` line; demote `^\[FAIL\]` to display; verdict = `^RED |^UNACCOUNTED ` or breakdown with `[1-9][0-9]* failed`; label unconfirmed `[FAIL]`-shaped lines
- [x] 2.2 Delete the raw `$(tail -30 "$file")` append and the orphaned `--- (tail) ---` header after the killed hits
- [x] 2.3 Add arm-4 `ACTIONS` (main unverified, read the step list and compare elapsed with ceiling, do not revert on this alone)
- [x] 2.4 Write per-step elapsed seconds to `$GITHUB_OUTPUT` after `rc=${PIPESTATUS[0]}`; pass via `env:` and emit only when `^[0-9]+$`; print in the `SOLEUR_MAIN_HEALTH` annotation and the filer's step-outcomes line
- [x] 2.5 Add the fifth defect entry to the workflow header; re-run the suite GREEN

## Phase 3: Budgets and Sentry envelope

- [x] 3.1 Measurement commit (workflow only): tests step 90 min, infra step 45 min, job `90 + 45 + 15`; dispatch window boundary+80 min to boundary+3 h; check no run is in flight or queued; dispatch once with `dry_run=true` on the branch; arm a Monitor watch
- [x] 3.2 Read `tests_elapsed_s` from the check-run annotation; confirm the runner printed its breakdown; cross-check against the 54 and 60 minute bounds
- [x] 3.3 Derive `tests_step = max(30, roundup5(1.5 * T_max))`, `job = tests + infra + 15`; update the TIMEOUT BUDGET comment (run id, arithmetic, branch-shape bias)
- [x] 3.4 Final commit (separate): derived ceilings, plus `max_runtime_minutes = job`, `checkin_margin_minutes = job + 25` and corrected comments in `apps/web-platform/infra/sentry/cron-monitors.tf`
- [x] 3.5 Infra ceiling: derive from the same dry run (subtract the #9379-named stalled suites if #9383 unmerged); if killed even at 45 min leave it and file the conditional follow-up (blocked-by #9383)

## Phase 4: Verification and ship

- [x] 4.1 Run the monitor test, `scripts/test-all-killed-classification.test.sh`, `plugins/soleur/test/scripts-shard-totality.test.sh`, `scripts/lint-diagnosis-claims.sh`, `scripts/lint-guard-contract.py`, `scripts/lint-infra-no-human-steps.py --changed --base origin/main`, and the sentry-monitor-iac-parity vitest suite
- [x] 4.2 Confirm the diff touches no git-data or apt-bounded path
- [x] 4.3 Post a corrective comment on #8112 before merge
- [ ] 4.4 PR body: `Closes #8112`, Changelog, residual-infra note, the new anti-vacuity floor number
- [ ] 4.5 Post-merge: `apply-sentry-infra.yml` success; `apply-web-platform-infra.yml` plans no change; non-dry-run dispatch reads `tests=success`; reopen #8112 with evidence if not

## Work-phase notes (recorded at implementation)

- Dry run 36950488321 (branch head a6ea0dde0, ceilings 90/45/150, uncensored): `tests_elapsed_s=4228`, `infra_elapsed_s=2326`, runner breakdown `549 suites: 547 passed, 1 failed` (the one failure was this PR's own G2 parity row, expected RED before the Terraform edit). Derived: tests 110, infra 60, job 185; Sentry `max_runtime_minutes=185`, `checkin_margin_minutes=210`.
- #9383 had merged by dispatch time, so the infra step was measured undisturbed and its ceiling was derived (task 3.5, first branch); no conditional follow-up filed.
- Deviation from the plan text: the filer's `Step outcomes` line prints the elapsed figures but not the step ceilings (the ceilings are static workflow literals and duplicating them into the filer would add a third copy to keep in step); arm-4 action 2 points at each step's `timeout-minutes` instead.
- The plan's `(8g)` is named `(8h)` in the suite because `(8g)` already existed.
- Mutation battery (sandbox copies, each mutation confirmed landed): `[FAIL]` re-admitted as verdict, `[1-9]` weakened, raw tail re-added, job ceiling +5, margin job+24, resource renamed: all RED; control GREEN.
- #9410's recorded trigger (a measured tests step above 60 minutes) is reached by this measurement (70.5 min).
