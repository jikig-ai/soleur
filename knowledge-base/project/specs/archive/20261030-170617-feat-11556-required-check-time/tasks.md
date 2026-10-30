# Tasks: required-check atomic-suite surgery (#11562, epic #11556)

Plan: `knowledge-base/project/plans/2026-10-29-ci-required-check-atomic-suites-plan.md`
Spec: `knowledge-base/project/specs/feat-11556-required-check-time/spec.md`

## Phase 1 — Diagnose `test-all-affected` divergence (G1)

- [x] 1.1 Read `scripts/test-all-affected.test.sh` phases (audit reach, naming walk, scan, mutation rows, live `gh` enumeration) and identify which is PR-event-sensitive
- [x] 1.2 Emit/obtain per-phase timing on one PR-shaped run (instrument locally or stub the diff surface)
- [x] 1.3 Decide split (`--rows` precedent, `shard-totality-mutations`) vs bound (pinned fixture corpus); record rationale in the PR body

## Phase 2 — Bound `ci-pr-affected-replay.test.sh` (G2)

- [x] 2.1 Partition the `row_*`/`rt_*`/`ow_*` arms of `plugins/soleur/test/ci-pr-affected-replay.test.sh` across in-runner labels (lint-orphan `-a`/`-b` shape — suite is fixture-stubbed, cost is ~469 mutant respawns)
- [x] 2.2 Retrofit ranged floors: `in_range` sequencing + DECLARED_TOTAL-style census so `FLOOR_ASSERTIONS`/`FLOOR_MUTANTS`/`OW_MUT_RUN` become ranged-sum equalities; register new `run_suite`/`skip_suite` labels inside the same gate arm
- [x] 2.3 Verify suite controls stay green (anti-vacuity floor, instrument self-test, mutant-crash-is-never-a-kill) — all 3 arms green (891/891/890 assertions, 85/193/192 mutants)

## Phase 3 — Apply the Phase-1 decision + regen manifests (G1/G3)

- [x] 3.1 Apply split/bound to `test-all-affected`; keep totality coverage (`scripts-shard-totality.test.sh`, 52-row battery green)
- [x] 3.2 Regen via `--timings-dir` over 5 green PR/merge_group runs + local arm-share estimates (light only — heavy unchanged); regen landed as isolated commit `fe302de771`; `.tsv.n` strays deleted
- [x] 3.3 `--legs K` dry-run for K ∈ {8,10,12} — all balanced; K stays 8 (predicted ~28.5 min/leg within bound; no K change)
- [x] 3.4 Fix stale ci.yml comments (~9.5 min/leg claims rewritten to point at manifest/runbook) + runbook topology table

## Phase 4 — Baseline + invariants verification (G4/G5)

- [x] 4.1 Fresh PR baseline via jobs API: worst `test-scripts` legs 49.4/51.0/43.2 min, leg spread ~22–32 min across runs 41037175716/41036790949/41030652561 — recorded in runbook Measured history 2026-10-30
- [x] 4.2 Verify CLO invariants: `scripts/required-checks.txt` byte-identical; `fetch-depth: 0` on CLA shard; `merge_group` synthetics intact; no `merge_group` concurrency-cancel
- [ ] 4.3 Post-PR observability: `suite-timings-*` leg spread ≤ ~10 min on a green run; worst leg ≤ ~28 min

## Acceptance Criteria

- Worst light leg ≤ ~28 min PR / merge_group critical path ≤ ~38 min
- Both manifests + durations regenerated via `--runs 5`; `# n=` header matches matrix N
- All guards green; no S4 affected-selection touch; runbook updated
