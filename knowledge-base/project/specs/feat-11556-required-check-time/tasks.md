# Tasks: required-check atomic-suite surgery (#11562, epic #11556)

Plan: `knowledge-base/project/plans/2026-10-29-ci-required-check-atomic-suites-plan.md`
Spec: `knowledge-base/project/specs/feat-11556-required-check-time/spec.md`

## Phase 1 — Diagnose `test-all-affected` divergence (G1)

- [ ] 1.1 Read `scripts/test-all-affected.test.sh` phases (audit reach, naming walk, scan, mutation rows, live `gh` enumeration) and identify which is PR-event-sensitive
- [ ] 1.2 Emit/obtain per-phase timing on one PR-shaped run (instrument locally or stub the diff surface)
- [ ] 1.3 Decide split (`--rows` precedent, `shard-totality-mutations`) vs bound (pinned fixture corpus); record rationale in the PR body

## Phase 2 — Bound `ci-pr-affected-replay.test.sh` (G2)

- [ ] 2.1 Identify the 25-min cost source inside `plugins/soleur/test/ci-pr-affected-replay.test.sh` (live `gh` run enumeration vs mutation rows)
- [ ] 2.2 Bound it: committed fixture corpus and/or `--rows` split; keep live enumeration exercised via the advisory `affected-index-ratchet` job
- [ ] 2.3 Verify suite controls stay green (anti-vacuity floor, instrument self-test, mutant-crash-is-never-a-kill)

## Phase 3 — Apply the Phase-1 decision + regen manifests (G1/G3)

- [ ] 3.1 Apply split/bound to `test-all-affected`; keep totality coverage (`scripts-shard-totality.test.sh`, 42-row battery green)
- [ ] 3.2 `python3 scripts/regenerate-shard-manifest.py --runs 5 --write` (light) and `--group heavy --runs 5 --write`
- [ ] 3.3 `--legs K` dry-run for K ∈ {8,10,12}; if K changes, same-commit ci.yml matrix + manifests
- [ ] 3.4 Fix stale ci.yml comments (~9.5 min/leg, "collected but not yet consumed") + runbook topology table

## Phase 4 — Baseline + invariants verification (G4/G5)

- [ ] 4.1 Fresh PR p90 baseline via jobs API (queue vs execution vs ejection-requeue decomposition); record in runbook Measured history
- [ ] 4.2 Verify CLO invariants: `scripts/required-checks.txt` byte-identical; `fetch-depth: 0` on CLA shard; `merge_group` synthetics intact; no `merge_group` concurrency-cancel
- [ ] 4.3 Post-PR observability: `suite-timings-*` leg spread ≤ ~10 min on a green run; worst leg ≤ ~28 min

## Acceptance Criteria

- Worst light leg ≤ ~28 min PR / merge_group critical path ≤ ~38 min
- Both manifests + durations regenerated via `--runs 5`; `# n=` header matches matrix N
- All guards green; no S4 affected-selection touch; runbook updated
