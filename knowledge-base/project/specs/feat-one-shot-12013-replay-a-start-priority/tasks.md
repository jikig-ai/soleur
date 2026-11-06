# Tasks: perf(tests): start the replay arms first in the local affected gate

Plan: `knowledge-base/project/plans/2026-11-06-perf-affected-gate-replay-start-priority-plan.md`
Issue: #12013 (use `Ref #12013`, never `Closes`). Deferred and not in this PR: #12151, #12152, reaping finished workers earlier, #12231.
Rulings: `decision-challenges.md` in this directory.

## Phase 0: Baseline and audits (no behaviour change)

- 0.1 Record the pre-change `bash scripts/test-all.sh --enumerate-commands all` output (label set, count, the three replay-arm rows) into the measurement notes.
- 0.2 `grep -n 'build_sandbox\|cp .*test-all.sh' scripts/*.test.sh tests/scripts/*.sh plugins/soleur/test/*.sh`; read each sandbox builder's splice anchors; confirm the moved lines stay inside the `tc_acquire "test-all"` .. `tc_epilogue` window.
- 0.3 Read `model.c4`, `views.c4`, `spec.c4` in full; run `bash plugins/soleur/test/c4-count-parity.test.sh` (green).
- 0.4 Run once as controls before editing: `scripts/lib/test-suite-lanes.test.sh`, `scripts/lint-orphan-test-suites.sh`, `plugins/soleur/test/scripts-shard-totality.test.sh`, `scripts/test-all-parallel-scheduler.test.sh`, `scripts/ci-oracle-lane.test.sh`, `scripts/guard-vacuity-floor.test.sh`. Re-verify that scripts-shard-totality (tiling) and ci-oracle-lane `MEMBER-ARGV-DRIFT` cover argv (CTO Q1 condition).

## Phase 1: Failing guard first

- 1.1 Add section 7 to `scripts/lib/test-suite-lanes.test.sh`: pure `start_first_ok <rows>` (each arm exactly once; bare suite path zero times; each arm's index below the first `*` row and the first `lock:test-all` row; `n_arms == 3` written as a statement), the live check on `--enumerate-commands all`, synthetic rows 2 to 6, must-PASS rows (`c a b`, longer non-arm list, a `*` and a `lock:test-all` row after the arms), and the runner-copy mutant (row 1) under the file's existing `_h_dir`. Update the header comment (sections 6 and 7).
- 1.2 Confirm section 7 is RED on the unmodified runner.

## Phase 2: Move the registrations

- 2.1 `scripts/test-all.sh`: insert the three `run_suite` lines (unchanged labels, literal argv) with the explanatory comment block at the top of the first `if want_scripts; then` block (before `run_suite "tests/hooks/incidents"`).
- 2.2 Glob loop: keep the `[[ "$f" == "plugins/soleur/test/ci-pr-affected-replay.test.sh" ]]` special case with only `continue` and a comment (the linters read that text).
- 2.3 Confirm section 7 GREEN; no change to `_pj_*`, `_shard_selects`, `run_suite`, lane values, shard tsv, durations tsv, `budget_seconds`.

## Phase 3: Structural gates

- 3.1 Re-run the Phase 0.4 suites: all green; registration count and label set identical to the Phase 0.1 record.

## Phase 4: Measurement (private clone, never a ship path)

- 4.1 Clone with its own git-common-dir; pin the diff pick `7af192071d`; set `origin/main` in the clone to the tree under test.
- 4.2 Control (same base, no edit), treatment 1; second treatment per the adaptive conditions. Detached, rc file, loadavg and heavy processes at start and end.
- 4.3 Before treatment: confirm `--enumerate-commands all` in the clone lists the arms ahead of the first `*` row.
- 4.4 Commit the raw rows and `summary.txt` under `measurements/`; record the model-versus-measured start for the control; state the number of readings.

## Phase 5: Record

- 5.1 ADR-242 amendment `## Amendment — 2026-11-06 (#12013)` via `soleur:architecture` (decision, headline numbers, does not claim 600 s, alternatives, pointers).
- 5.2 PR body: `Ref #12013`; the CI run is not the measurement; deferral section naming #12231, #12151, #12152 and the reap evidence bar.
- 5.3 After merge (agent-run): comment on #12013 with the result and the remaining gap; it stays open.
