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

- 1.1 Add section 7 to `scripts/lib/test-suite-lanes.test.sh`: pure `start_first_ok` over `label<TAB>tokens` rows (raw rows, not the deduplicated map): each arm exactly once; bare suite path zero times; each arm's 1-based index at most `W` (named constant 4, tracking the gate's `SOLEUR_TEST_JOBS`); no `*` token before the last arm (tokens resolved only for those rows, literal tokens in synthetic rows); `n_arms == 3` written as a statement. Live check on `--enumerate-commands all`; synthetic rows 2 to 7; must-PASS rows (`c a b`, a token-free suite above the arms, longer non-arm list, a `*` and a `lock:test-all` row after the arms); the runner-copy mutant (row 1: `$sb/scripts/test-all.sh`, `lib` symlinked, shard tsv copied, under the file's existing `_h_dir`, regex asserted to extract 3 lines). Store section 1's tokens in `tok_of[$label]` for reuse. Raise the `(( PASSES < 12 ))` floor by the number of section 7 passes. Update the header comment (sections 6 and 7).
- 1.2 Confirm section 7 is RED on the unmodified runner.

## Phase 2: Move the registrations

- 2.1 `scripts/test-all.sh`: insert the three `run_suite` lines (unchanged labels, literal argv) with the explanatory comment block at the top of the first `if want_scripts; then` block (before `run_suite "tests/hooks/incidents"`).
- 2.2 Glob loop: keep the `[[ "$f" == "plugins/soleur/test/ci-pr-affected-replay.test.sh" ]]` special case with only `continue` and a comment (the linters read that text).
- 2.3 Confirm section 7 GREEN; no change to `_pj_*`, `_shard_selects`, `run_suite`, lane values, shard tsv, durations tsv, `budget_seconds`.

## Phase 3: Structural gates

- 3.1 Re-run the Phase 0.4 suites plus `scripts/lint-orphan-test-suites.test.sh`, `scripts/lib/repo-write-boundary.test.sh`, `scripts/test-all-group-affected.test.sh`, `scripts/test-all-capacity-signal.test.sh`, `scripts/test-all-orphan-log-retention.test.sh`, `plugins/soleur/test/fanout-suite-scope.test.sh`, `plugins/soleur/test/collision-precheck.test.sh`, the `scripts/test-all-affected*.test.sh` family and `scripts/test-all-pr-battery-gate.test.sh`: all green; label set and argv identical to `measurements/before.enum.tsv` (sorted diff empty). Block comment hygiene: no comment line starts with `run_suite ` or quotes `"$f" == `.

## Phase 4: Measurement (private clone, never a ship path)

- 4.1 Clone with its own git-common-dir; pin the diff pick `7af192071d`; set `origin/main` in the clone to the tree under test.
- 4.2 Control, treatment, control (second control if the treatment gain is within 150 s of the bar or the readings look disturbed). Clear the derive cache before each reading and record its state; pool start = the `[parallel] mode engaged` line. Detached, rc file, loadavg and heavy processes at start and end. The `replay-a` start offset is the only hard gate; the pool-phase delta is gated against the mean of the controls (advisory if the controls differ by more than 100 s).
- 4.3 Before treatment: confirm `--enumerate-commands all` in the clone lists the arms ahead of the first `*` row.
- 4.4 Commit the raw rows and `summary.txt` under `measurements/`; record the model-versus-measured start for the control; state the number of readings.

## Phase 5: Record

- 5.1 ADR-242 amendment `## Amendment — 2026-11-06 (#12013)` (next decision number per ADR-242's convention) via `soleur:architecture`: decision, headline numbers, does not claim 600 s, alternatives, pointers, plus the budget-kill note, the serial-fallback note, the `*`-barrier trade-off (#12231).
- 5.2 PR body: `Ref #12013`; the CI run is not the measurement; deferral section naming #12231, #12151, #12152 and the reap evidence bar.
- 5.3 After merge (agent-run): comment on #12013 with the result and the remaining gap; it stays open.
