# Measurements — test-scripts K=6→K=7 rebalance (2026-09-25)

## Before (pre-change)

| Metric | Value | Source |
|---|---|---|
| Worst `test-scripts` leg (suite time) | 12.9 min (leg 6/6) | run 36123485360 `suite-timings-scripts-*` artifacts |
| Worst `test-scripts` leg (wall) | ~13.0 min | run 36123485360 jobs API |
| Light-leg spread (suite time) | 7.6–12.9 min | run 36123485360 artifacts |
| Total CI job-min per run | ~108 | run 36123485360 (suite growth 374→505 registrations vs 374-era ~53 job-min baseline run 32415069661, 2026-08-20) |
| Registered light suites | 502 | `bash scripts/test-all.sh --enumerate scripts | wc -l` |
| K=6 dry-run regen prediction (worst leg) | 614.0 s (10.23 min suite time) | `regenerate-shard-manifest.py --run 36125573947` dry-run, 2026-09-25 |

Gate: predicted worst ≥ 9.5 min suite time → K bump (per plan §Phase 2a).

## Change applied

- ci.yml `test-scripts` matrix `["1/6".."6/6"]` → `["1/7".."7/7"]`; K=6→K=7
  comment restatements (job header, timeout nominal, artifact-name example,
  heavy-job "fans out" comment).
- `scripts/suite-shard-legs.tsv` regenerated from run 36125573947 (`# n=7`).
- `scripts-shard-totality-mutations.sh` ROW5 match/mutant literals → /7;
  `scripts-shard-totality.test.sh` ROW5-shape comment → /7.
- Runner-slot cost: +1 leg ≈ +0.4 job-min/run, one more slot against the
  org concurrency ceiling.

## After (predicted, from regenerator on run 36125573947)

| Leg | Suite time | Wall est. (+~0.4 min setup) |
|---|---|---|
| 1/7 | 506.4 s | ~8.8 min |
| 2/7 | 506.7 s | ~8.9 min |
| 3/7 | 498.1 s | ~8.7 min |
| 4/7 | 496.8 s | ~8.7 min |
| 5/7 | 588.8 s | ~10.2 min |
| 6/7 | 495.0 s | ~8.7 min |
| 7/7 | 486.2 s | ~8.5 min |

Leg 5 is a single atomic suite (`scripts/lint-orphan-test-suites-mutations`,
588.8 s measured) — no K splits it; the suite-internal split/move is the
deferred follow-up issue. Post-merge green-run wall-clock measurement for
AC1 recorded here after merge.
