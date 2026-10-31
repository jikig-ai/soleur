# Learning: decompose CI leg wall-clock from suite-timings artifacts before attributing overhead vs suite

## Problem

Epic #11556 scoped a Lever-A fix (rebalance shards, cache re-downloaded deps) for two 54/50-min `test-scripts` legs. Four independent domain leaders (CTO/CPO/CLO/COO) each hypothesized ~14 min/leg of fixed setup overhead as the dominant cost — because predicted suite time (~15 min/leg) was far below measured wall-clock (~55 min). Caching the "re-downloads" was the epic's biggest lever.

## Solution

Download the run's own `suite-timings-scripts-{0..7}` artifacts (`gh run download <run> -n suite-timings-scripts-N` — needs `-R owner/repo` on this host, and artifacts live ~14 days) and sum column 2 per leg. Result: **suite-sum ≈ wall-clock on every leg** (54.2≈54.9, 50.1≈50.9, setup ≈ 1 min, not 14). Two atomic suites carried the whole anomaly: `ci-pr-affected-replay.test.sh` priced 1,184 ms at floor but measured 24.9 min (never measured on main — fresh S4 tooling), and `test-all-affected` at 5.3× its main median on PR events. The merge_group run showed the SAME two suites dominating — "merge_group costs as much as the PR run" was the same atomic floor, not duplication.

## Key Insight

- **The timings artifact settles overhead-vs-suite directly; don't hypothesize the split.** All four leaders independently landed on "fixed overhead" because wall−predicted looked like overhead — but the floor-priced suite's real cost was inside the suite column the whole time.
- **Floor-priced manifest rows are unpriced risk.** A suite never measured in the last-5-green-main-runs sample keeps a ~1 s floor price through every `--incremental` regen; it can grow to 25 min before any balance check notices. Never-measured + floor = grep the durations TSV for `floor` rows before trusting a pack prediction.
- **PR-event behavior ≠ main medians.** The packing source is green `push`-run medians; suites that derive from the PR diff (affected-selection tooling) inflate severalfold on `pull_request` — price-check against the event you're optimizing.
- The atomic-floor rule decides the lever: worst leg ≥ largest indivisible suite → suite split/bound, not rebalance.

## Session Errors

1. `bash cloud-detect.sh` failed with a path-less error — env-prefix `VAR=x bash "$VAR/script"` expands `$VAR` before the assignment applies. **Recovery:** literal path. **Prevention:** none — one-off.
2. First `gh issue create` refused by the filing gate for missing `--milestone`. **Recovery:** added `--milestone`. **Prevention:** none — discovered via the gate's own clear error (discoverability exit).
3. `gh run download <run> -n <artifact>` produced nothing silently without `-R`. **Recovery:** listed artifacts via `gh api .../artifacts`, retried with `-R`. **Prevention:** none — one-off.

## Tags

category: workflow-patterns
module: ci
