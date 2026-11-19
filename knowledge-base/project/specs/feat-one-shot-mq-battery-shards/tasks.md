# Tasks — feat-one-shot-mq-battery-shards

Derived from `knowledge-base/project/plans/2026-11-19-feat-mq-battery-shard-rebalance-k12-plan.md`. Lane: single-domain.

## Phase 1 — Fresh merge_group measurements + dry-run sizing (no writes)

- [ ] 1.1 Re-list the last 5 green merge_group ci.yml runs: `gh run list --workflow ci.yml --event merge_group --status success -L 5` (plan-time sample: 44485722708, 44422317370, 44367783886, 44361074603, 44341020337 — refresh at work time).
- [ ] 1.2 Download each run's `suite-timings-*` artifacts to per-run dirs: `gh run download <id> -R jikig-ai/soleur -p 'suite-timings-*' -D <dir>`.
- [ ] 1.3 Run `python3 scripts/regenerate-shard-manifest.py --drift-report --timings-dir <5 dirs>`; record `LEG_OBSERVED`, `BOUND_PERFECT`, `PRICE_DRIFT_ROW` output for the PR body.
- [ ] 1.4 Dry-run arbitrary-K packings at K ∈ {10, 12, 14} (`--durations <fresh> --legs K --manifest /tmp/legs-K.tsv`); record predicted per-leg tables.
- [ ] 1.5 Confirm K per the smallest-K-above-heavy rule (predicted: K=12); if fresh medians shift the heavy wall, fall back per the rule and note it.

## Phase 2 — Generator source hardening (P4)

- [ ] 2.1 Add `--event {auto,push,merge_group}` (or equivalent) to `scripts/regenerate-shard-manifest.py` so ci.yml-group `--runs` defaults to merge_group runs; infra keeps its current source.
- [ ] 2.2 Refuse a committed `--write` when measured-input count is zero, absent an explicit acknowledge flag (kills the all-floor footgun).
- [ ] 2.3 Add fixture rows to `plugins/soleur/test/regenerate-shard-manifest.test.sh` covering both behaviors.

## Phase 3 — K bump + regeneration (coupled edits)

- [ ] 3.1 `.github/workflows/ci.yml`: `test-scripts` matrix `["1/8"…"8/8"]` → `["1/12"…"12/12"]`; update K prose (L1779–1780, L1983 `1/8` example, L2006, L245).
- [ ] 3.2 `.github/workflows/main-health-monitor.yml`: same literal (L482) + comments (L57–68, L471–472). Same commit as 3.1 — shared manifest.
- [ ] 3.3 Regenerate light pair: `python3 scripts/regenerate-shard-manifest.py --timings-dir <5 dirs> --write`; if the drift gate refuses, review the violation list then re-run with `--allow-growth` and paste violations into the PR body.
- [ ] 3.4 Reprice heavy: `python3 scripts/regenerate-shard-manifest.py --group heavy --timings-dir <5 dirs> --write`.
- [ ] 3.5 Update `plugins/soleur/test/scripts-shard-totality-mutations.sh` ROW5 `old`/`new` literals to the 12-value matrix (old = new ci.yml bytes; new drops `"12/12"`).
- [ ] 3.6 Prose sweep: `plugins/soleur/test/scripts-shard-totality.test.sh` L10/L177, any other "eight legs"/`n=8` prose, `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` topology table + measured-history entry + monitor coupling.
- [ ] 3.7 Sentinel sweep before push: `scripts-shard-totality.test.sh`, `scripts-shard-totality-mutations.sh`, `regenerate-shard-manifest.test.sh`, `scripts-shard-manifest.test.sh`, `scripts-shard-runtime-coverage.test.sh`, `ci-shard-totality-skip.test.sh`, `watch-shard-balance-11564.test.sh` — all green.

## Phase 4 — Post-merge verification

- [ ] 4.1 On the first green merge_group run after merge: `gh run view <id> --json jobs` — worst `test-scripts` leg < 30 min wall (expect ~20–22); battery/`test` umbrella < 30 min; `test-scripts-heavy (1/3)` not the new tail.
- [ ] 4.2 Comment the verification result on the PR (AC7).

## Deferred (do NOT implement in this PR)

- `--rows` split of `registry-gate-mutation-battery` — only if its fresh median > ~20 min or heavy becomes the recurring tail (decision-challenges.md).
- `watch-shard-balance-11564.sh` leg-ratio bound tuning — taste item, left for operator.
- Per-suite time surgery (`ci-head-verdict`, `monitor-pr-checks`) — absorbable by packing.
