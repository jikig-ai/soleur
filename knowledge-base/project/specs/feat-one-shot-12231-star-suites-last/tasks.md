# Tasks: perf(tests): run the drain-barrier (*) suites last, then rebalance the replay arms

Plan: `knowledge-base/project/plans/2026-11-06-perf-affected-gate-star-suites-last-and-replay-rebalance-plan.md`
Issue: #12231 (`Ref #12013`; follow-up #12263). Branch: feat-one-shot-12231-star-suites-last. Draft PR: #12261.

## Phase 0: Baseline and tooling
- 0.1 Record the sorted `--enumerate-commands` rows (scratch, not committed)
- 0.2 Copy `derive.sh` and the method text from the archived measurements; write `measure.sh` (clone, symlink both `node_modules`, pinned diff `7af192071d`, stamped output, loadavg and foreign-pid record, abort on a disturbed start, one summary line per reading)

## Phase 1: RED - scheduler arms (`scripts/test-all-parallel-scheduler.test.sh`)
- 1.1 Retarget bf3 and A4b (long-holder shape `indA, starS, slowL, indB`; marker, timing-log order, numeric `tmp_delta`); clause-naming labels on every `tl_check`; raise `MIN_PASSES_FLOOR`
- 1.2 Add arms: blocked-head star, two stars (override `*` with timelines) + derived-`*` arm (`[run]` order, expects `[FAIL]`), drain-order, star-first (runner-written ordering), torn reap `holdT, starS`, signal-while-parked (`starS` registered first), multi-token (mandatory)
- 1.3 FIFO control arm: record the frozen literal by running it on the UNMODIFIED runner (the anchor)
- 1.4 Must-PASS shapes (`*` registered last; no `*` suite), instrument self-test for the `star` label, re-seed the `many` arm ceiling (about 200) and add the `[run]`-order assertion; C3 in `test-all-parallel-contention.test.sh`: header and a started/done presence assertion
- 1.5 Run against the unmodified runner: new arms RED for their own reason, FIFO/must-PASS/instrument GREEN. Commit C-tests (do not push alone)

## Phase 2: GREEN - park and release (`scripts/test-all.sh`)
- 2.1 `_pj_draining=0` declared beside `_pj_fifo` in the pre-splice state block; set to 1 at the top of `_pj_drain`
- 2.2 Backfill branch of `_pj_fill`: always park a `*` token set (word-bounded test), no `skip_tok`/`any_q`
- 2.3 Post-loop: if `_pj_draining` and `_pj_live_n == 0` and `rest` non-empty, launch `rest[0]`
- 2.4 Rewrite stale prose once in the `_pj_fill` block; point the `SOLEUR_PJ_FIFO` header, design comment, START-FIRST comment, `test-suite-lanes.sh` THE MODEL paragraph and `test-suite-lanes.test.sh` section-7 header at it
- 2.5 Run: scheduler suite, contention, benchmark, lanes test, capacity-signal, orphan-process-reaper (+mutation), every suite that copies the runner. Commit C-impl with ADR-242 Decision 30

## Phase 3: Mutants and enumeration
- 3.1 Run Guard 1 mutants M1a to M9 via `TESTALL_TARGET_OVERRIDE`; outcome table into `summary.txt`
- 3.2 Re-take the enumeration; diff must be empty

## Phase 4: Rebalance (gated, one droppable commit)
- 4.0 Paper check `measurements/rebalance_whatif.py` (baseline must reproduce 1611 s / 945 s); proceed only on a predicted gain of at least 30 s, else record "not landed, paper-negative" and skip 4.1 to 4.4 and T2
- 4.1 Throwaway `in_range` timing hook; per-site cost and unconditional share from the three arms run concurrently; commit `site-costs.tsv`
- 4.2 Two-cut search minimizing the simulated pool end; `split.py` + output
- 4.3 One commit: three `run_suite` lines, `ci-oracle-lane-suites.txt`, the drift-mutant `sed` literal derived from the manifest, three rows of `suite-durations.tsv` (`src=estimate`), the replay-a row of `suite-weight-exemptions.tsv`; regen only as a no-diff check
- 4.4 Run totality, ci-oracle-lane, lanes test, weight-drift, corpus-weight-budget, affected-index ratchet, each new arm standalone; Guard 2 matrix once

## Phase 5: Cold readings (quiet host, no editing)
- 5.1 C (merge-base tree, `SOLEUR_PJ_FIFO` unset), T1 (C-impl); T2 only if Phase 4.0 passed; C2 per the plan rule
- 5.2 Derive with `derive.sh`; wait with Monitor, never polling

## Phase 6: Evidence and hand-off
- 6.1 `measurements/summary.txt` (method, table, mutant outcomes, caveats, not-claimed)
- 6.2 ADR-242 Decision 31 only if the rebalance landed; runbook line 18
- 6.3 Full battery (`bash scripts/test-all.sh`) with all six `*` verdicts green; `lint-guard-contract.py`
- 6.4 PR body: `Ref #12013`; `Closes #12231` only per AC7; rebalance wording per AC8; expected CI effect; note on #12263 if lever 2 is paper-negative
