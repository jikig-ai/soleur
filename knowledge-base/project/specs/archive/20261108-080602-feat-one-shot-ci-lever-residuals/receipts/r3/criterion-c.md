# Criterion (c) re-measurement — billed job-minutes per pull_request run (S4 third re-ruling, Ref #9729)

Measured 2026-11-08. Two legs: (1) net saving ≥ 20% of a FRESH ci.yml pull_request baseline; (2) restored
selection plus overhead ≤ 120 s (the PR C canary, cited unchanged).

## Baseline (the bar)

`bash scripts/ci-demand-census.sh --start <t0> --end <t1> --workflow ci.yml --summary` over two adjacent closed
12-hour windows (the script's maximum span), combined per its LONGER SPANS recipe (minutes and runs summed, the
per-run figure recomputed):

| Window (UTC) | pull_request completed runs | ci.yml pull_request job-minutes | per run |
|---|---|---|---|
| 2026-11-07T20:00Z → 2026-11-08T08:00Z | 118 | 12,318.4 | 104.39 |
| 2026-11-08T08:00Z → 2026-11-08T20:00Z | 137 | 13,745.9 | 100.34 |
| **Combined** | **255** | **26,064.3** | **102.21** |

The 99.8 baseline predates S3/push-dedupe/umbrella/oracle changes; the fresh figure is **102.21 billed
job-minutes per pull_request run** (down from 120.17 on 2026-11-07 — the windows moved and the mix shifted),
so the bar is **20.44** (20%).

Leg-execution shares from the same STEM rows (why the second reading below exists): `test-scripts` ran on
90 of 255 PR runs (35.3%), `test-scripts-heavy` 90 (35.3%), `test-webplat` 90 (35.3%), `test-bun` 201 (78.8%);
the rest were gate-skipped or runner-less — light runs already pay nothing on those legs, so the lever's
marginal saving on them is ~0. `affected-index-ratchet` billed ~343.4 + 377.3 min over the two windows
(~2.8–3.3 min per PR run it ran on, consistent with the ~3.4 debit below). `pr-selection` ran 0 times
(the dark job stays skipped while `CI_PR_AFFECTED` is unset).

## Saving leg (the prescribed measurement)

Sample: the 20 most recent completed `pull_request` runs with conclusion `success`
(`gh run list --workflow ci.yml --event pull_request --status success -L 20`, run 2026-11-08 ~22:45Z).
PR resolution: 3 runs resolved via the run's `pull_requests` array; **17 resolved via
`gh pr list --head <branch> --state all -L 1`** because merged-PR runs now return an empty
`pull_requests` array (a platform-side change since the R2 run resolved all 20 directly — disclosed, the
recipe is unchanged). Every one ran the full battery (all four suite legs `success` in the jobs API).
Per PR: changed files from `gh api repos/jikig-ai/soleur/pulls/<n>/files`; selection from
`env -u CI -u SOLEUR_TEST_FORCE_ALL bash scripts/test-all.sh --print-selection --paths=<list>` on this
worktree; the would-be-skipped set = `AFFECTED_SELECTED` rows `sel=0` and class ≠ `always_on`; priced via
`scripts/suite-durations{,-heavy}.tsv` (a label absent from both tables counts 1.18 s — a lower bound on the
web-platform/bun registrations, which carry no duration rows).

Raw rows (run_id, PR, changed files, selector fallback, would-be-skipped suite-minutes):

```
run_id      	pr	files	fallback      	skip_min	rows_sel0	ts-leg	heavy+other
42527348174 	12445	1   	none          	103.08 	569 	102.92 	0.16
42526090695 	12442	2   	none          	151.16 	631 	150.91 	0.26
42521863710 	12410	17  	runner-changed	0.00   	0   	0.00   	0.00
42520189031 	12419	15  	none          	72.20  	446 	71.97  	0.24
42517840958 	12410	17  	runner-changed	0.00   	0   	0.00   	0.00
42515855906 	12419	15  	none          	72.20  	446 	71.97  	0.24
42514582451 	12430	5   	none          	121.43 	625 	121.20 	0.24
42514052601 	12431	1   	none          	103.07 	568 	102.91 	0.16
42511839184 	12412	13  	runner-changed	0.00   	0   	0.00   	0.00
42497255658 	12415	12  	none          	107.00 	585 	106.86 	0.14
42490350427 	12342	57  	none          	60.53  	395 	60.39  	0.14
42486533493 	12342	57  	none          	60.53  	395 	60.39  	0.14
42483514692 	12377	20  	runner-changed	0.00   	0   	0.00   	0.00
42483511744 	12378	13  	none          	61.07  	428 	60.83  	0.24
42481673225 	12388	5   	none          	107.02 	586 	106.88 	0.14
42478799967 	12357	41  	runner-changed	0.00   	0   	0.00   	0.00
42478454449 	12404	3   	none          	103.48 	566 	103.25 	0.24
42476576581 	12391	21  	none          	61.47  	407 	61.34  	0.14
42475778360 	12387	8   	none          	113.75 	610 	113.49 	0.26
42474322644 	12354	27  	none          	71.28  	454 	71.05  	0.24
```

Five PRs edit the runner or its oracle inputs (`scripts/test-all.sh` family / ci.yml / replay tool) →
`fallback=runner-changed` → the rule runs the full battery; saving 0, correctly. The runner-changed share
(5 of 20) is higher than R2's (2 of 20) — a CI-heavy merge window.

- **Reading 1 (the sample as drawn — full-battery runs):** mean gross **68.46** suite-min/run (se 10.51);
  net of the ~1 billed min `pr-selection` job and the ~3.4 billed min/run advisory-ratchet debit the
  2026-10-22 amendment counts against this criterion: **64.06** ≥ 20.44. Even mean − 2se − debits ≈ 43.0.
- **Reading 2 (all pull_request runs, the bar's own denominator):** the priced axis is the `test-scripts`
  leg (~99.7% of every row's skipped minutes), which ran on 35.3% of the window's PR runs; runs where the
  light gate already skipped the leg yield ~0 marginal saving. Population estimate ≈ 0.353 × 68.46 − 4.4
  ≈ **19.76** vs the bar **20.44** — 96.7% of threshold, **inside the 10% band but not over it**.
  (Skips concentrate on docs-light diffs that would skip even more, so weighting by the run share is
  conservative only if run-vs-skip correlation is mild; both readings are recorded rather than asserted.)

## Timing leg (restored selection + overhead ≤ 120 s)

Unchanged from the PR C canary (`receipts/sel-s-canary.md` in the 2026-10-16 archive): cold pass 146 s,
warm 13 s → ~29 s job path, one billed minute; ≤ 120 s holds.

## Status for criterion (c): `within-10%`

The criterion's own denominator is billed job-minutes per **pull_request run** — the whole population, where
the weighted reading lands 19.76 vs 20.44 (−3.3%, inside the 10% band, not a pass, not an outside-band fail).
The per-full-battery-run reading passes plainly (64.06 ≥ 20.44); the timing leg holds. Limits, stated:
suite-minutes ≈ billed job-minutes at first order (a skipped suite shortens its shard job; a wholly-skipped
leg saves its full bill), the sample's 20 runs are consecutive successful runs not a random draw, the five
runner-changed rows show the fallback correctly zeroes saving, the default 1.18 s for unpriced labels
under-counts the web-platform/bun axis, and the 17 branch-resolved PRs are the same runs R2's recipe would
have taken — the resolution path changed, the sample did not.
