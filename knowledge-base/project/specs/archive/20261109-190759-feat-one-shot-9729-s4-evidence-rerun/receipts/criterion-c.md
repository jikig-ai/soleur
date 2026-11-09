# Criterion (c): billed minutes saving — 2026-11-09

## Baseline (two adjacent closed 12h windows, ci-demand-census.sh --workflow ci.yml)

- w1 2026-11-08T22:00Z→2026-11-09T10:00Z: 50 pull_request runs (= 53 pull_request runs in census − 3 RUNS_NOJOBS), 5,182 job-min → 103.65/run (TOTAL_JOB_MINUTES=11,385.6 all events; 1 not-yet-completed run excluded → lower bound)
- w2 2026-11-08T10:00Z→22:00Z: 131 pull_request runs (= 140 − 9 RUNS_NOJOBS), 14,828 job-min → 113.19/run (TOTAL_JOB_MINUTES=25,298.8)
- Combined baseline M = 20,010/181 ≈ **110.55** billed job-min per PR run; bar = 0.20·M ≈ **22.11**
- `test-scripts` leg ran on 61/181 PR runs = **33.7%** (population weight); `affected-index-ratchet` billed ~3.33/2.89 min per PR run; `pr-selection` ran 0 (dark, CI_PR_AFFECTED unset)

## Saving leg — 20 most recent completed pull_request success ci.yml runs (2026-11-09 ~11:20Z)

Same recipe as R3: PR resolution via `pull_requests` array else `gh pr list --head <branch> --state all -L 1` (merged-PR runs return empty array); changed files via `gh api .../pulls/<n>/files`; selection via `env -u CI -u SOLEUR_TEST_FORCE_ALL bash scripts/test-all.sh --print-selection --paths=<list>` on this worktree; would-be-skipped = `AFFECTED_SELECTED` rows `sel=0` and class ≠ `always_on`; priced via `scripts/suite-durations{,-heavy}.tsv` (unpriced label = 1.18 s).

One measurement artifact, fixed: run 42520189031's first selection produced empty output (killed mid-run on a loaded host); re-ran it — 445 sel0 rows / 71.45 skip-min, consistent with its sibling run 42515855906 (same PR+files).

Raw rows (sample-rows.tsv): run_id, pr, files, fallback, skip_min, rows_sel0, ts-leg, heavy+other.

4 runner-changed rows (12446, 12410×2, 12412 → full battery, saving 0, correctly). 16 priced rows.

- **Reading 1 (sample as drawn):** mean gross **73.35** suite-min/run (se 9.79); net of ~1 + ~3.3 debits ≈ **69.05 ≥ 22.11**. Even mean − 2se − debits ≈ 49.3.
- **Reading 2 (population-weighted by leg share, the bar's denominator):** 0.337 × 73.35 − ~4.3 ≈ **20.4** vs bar **22.11** — ~92% of threshold, **inside the 10% band, not over**.

## Timing leg

Unchanged from PR C canary: ~29 s job path, one billed minute; ≤ 120 s holds.

## Status for criterion (c): `within-10%`

Per-full-battery-run reading passes plainly; population-weighted lands ~92% of bar (inside band, not a pass).
Limits: suite-minutes ≈ billed job-minutes first-order; 20 consecutive successful runs not a random draw;
runner-changed rows correctly zero saving; 1.18 s floor under-counts web-platform/bun axis; w1 excluded one
still-running run (lower bound on M).

Note: `replay-summary.txt`'s `saving` line uses the tool default `--baseline-min 99.8` (bar_min=19.96); this file's census-derived baseline (110.55, bar 22.11) is authoritative for criterion (c).
