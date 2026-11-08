# Criterion (c) re-measurement — billed job-minutes per pull_request run (S4 re-ruling, Ref #9729)

Measured 2026-11-07. Two legs: (1) net saving ≥ 20% of a FRESH ci.yml pull_request baseline; (2) restored
selection plus overhead ≤ 120 s (the PR C canary, cited unchanged).

## Baseline (the bar)

`bash scripts/ci-demand-census.sh --start <t0> --end <t1> --workflow ci.yml --summary` over two adjacent closed
12-hour windows (the script's maximum span), combined per its LONGER SPANS recipe (minutes and runs summed, the
per-run figure recomputed):

| Window (UTC) | pull_request completed runs | ci.yml pull_request job-minutes | per run |
|---|---|---|---|
| 2026-11-06T20:00Z → 2026-11-07T08:00Z | 47 | 7,749.8 | 164.89 |
| 2026-11-07T08:00Z → 2026-11-07T20:00Z | 156 | 16,644.4 | 106.69 |
| **Combined** | **203** | **24,394.2** | **120.17** |

The 99.8 baseline predates S3/push-dedupe/umbrella/oracle changes; the fresh figure is **120.17 billed
job-minutes per pull_request run**, so the bar is **24.03** (20%).

Leg-execution shares from the same STEM rows (why the second reading below exists): `test-scripts` ran on
80 of 203 PR runs (39.4%), `test-scripts-heavy` 79 (38.9%), `test-webplat` 79 (38.9%), `test-bun` 144 (70.9%);
the rest were gate-skipped or runner-less — light runs already pay nothing on those legs, so the lever's
marginal saving on them is ~0. `affected-index-ratchet` billed 403.0 + ~110.8 min over the two windows
(~2.6–3.8 min per PR run, consistent with the ~3.4 debit below).

## Saving leg (the prescribed measurement)

Sample: the 20 most recent completed `pull_request` runs with conclusion `success`
(`gh run list --workflow ci.yml --event pull_request --status success -L 20`, run 2026-11-07 ~22:30Z),
resolved to their PRs (one run per row; PRs 12310 and 12341 appear twice — two pushes each).
Every one ran the full battery (all four suite legs `success` in the jobs API).
Per PR: changed files from `gh api repos/jikig-ai/soleur/pulls/<n>/files`; selection from
`env -u CI -u SOLEUR_TEST_FORCE_ALL bash scripts/test-all.sh --print-selection --paths=<list>` on this
worktree; the would-be-skipped set = `AFFECTED_SELECTED` rows `sel=0` and class ≠ `always_on`; priced via
`scripts/suite-durations{,-heavy}.tsv` (a label absent from both tables counts 1.18 s — a lower bound on the
web-platform/bun registrations, which carry no duration rows).

Raw rows (run_id, PR, changed files, selector fallback, would-be-skipped suite-minutes):

```
run_id      	pr	files	fallback      	skip_min	rows_sel0	ts-leg	heavy+other
42383089070 	10928	26  	runner-changed	0.00   	0   	0.00   	0.00
42381457232 	12294	19  	runner-changed	0.00   	0   	0.00   	0.00
42399161122 	12295	19  	none          	52.35  	386 	52.11  	0.24
42398617467 	12306	13  	none          	60.40  	395 	60.26  	0.14
42376301367 	12307	12  	none          	61.75  	402 	61.61  	0.14
42414780680 	12310	80  	none          	113.60 	610 	113.36 	0.24
42408271429 	12310	80  	none          	113.60 	610 	113.36 	0.24
42377488735 	12312	1   	none          	150.83 	625 	150.57 	0.26
42398715253 	12313	9   	none          	64.19  	421 	64.06  	0.14
42379564041 	12316	2   	none          	150.83 	625 	150.57 	0.26
42405708661 	12325	5   	none          	65.05  	416 	64.92  	0.14
42405404363 	12326	8   	none          	72.72  	450 	72.48  	0.24
42397029772 	12327	1   	none          	150.83 	625 	150.57 	0.26
42407996104 	12330	2   	none          	101.36 	558 	101.20 	0.16
42408145078 	12331	7   	none          	62.61  	398 	62.48  	0.14
42405005544 	12334	1   	none          	150.83 	625 	150.57 	0.26
42407802270 	12338	1   	none          	148.56 	622 	148.32 	0.24
42416091076 	12341	17  	none          	63.19  	413 	63.05  	0.14
42408989754 	12341	17  	none          	63.19  	413 	63.05  	0.14
42416598151 	12353	2   	none          	102.27 	556 	102.13 	0.14
```

Two PRs edit the runner (`scripts/test-all.sh` / `scripts/lib/test-affected-paths.sh`) →
`fallback=runner-changed` → the rule runs the full battery; saving 0, correctly.

- **Reading 1 (the sample as drawn — full-battery runs):** mean gross **87.41** suite-min/run (se 10.58);
  net of the ~1 billed min `pr-selection` job and the ~3.4 billed min/run advisory-ratchet debit the
  2026-10-22 amendment counts against this criterion: **83.01** ≥ 24.03. Even mean − 2se − debits = 65.8.
- **Reading 2 (all pull_request runs, the bar's own denominator):** the priced axis is the `test-scripts`
  leg (~99.8% of every row's skipped minutes), which ran on 39.4% of the window's PR runs; runs where the
  light gate already skipped the leg yield ~0 marginal saving. Population estimate ≈ 0.394 × 87.4 − 4.4
  ≈ **30.0** ≥ 24.03. (Skips concentrate on docs-light diffs that would skip even more, so weighting by the
  run share is conservative only if run-vs-skip correlation is mild; both readings are recorded rather than
  asserted.)

## Timing leg (restored selection + overhead ≤ 120 s)

Unchanged from the PR C canary (`receipts/sel-s-canary.md` in the 2026-10-16 archive): cold pass 146 s,
warm 13 s → ~29 s job path, one billed minute; ≤ 120 s holds.

## Status for criterion (c): `pass`

Net saving ≥ 20% of the fresh 120.17 baseline under both the per-full-run and the population-weighted
reading; the timing leg holds. Limits, stated: suite-minutes ≈ billed job-minutes at first order (a skipped
suite shortens its shard job; a wholly-skipped leg saves its full bill), the sample's 20 runs are consecutive
successful runs not a random draw, the two runner-changed rows show the fallback correctly zeroes saving, and
the default 1.18 s for unpriced labels under-counts the web-platform/bun axis.
