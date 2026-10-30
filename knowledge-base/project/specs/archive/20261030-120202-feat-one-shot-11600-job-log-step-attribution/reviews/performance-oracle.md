# Performance Oracle review — PR #11603 (feat-one-shot-11600-job-log-step-attribution)

Scope: `git diff origin/main...HEAD` in the worktree. Perf-relevant surface is
`scripts/followthroughs/web-first-deploy-10585.sh` (the daily-sweep probe,
`scheduled-followthrough-sweeper.yml` cron `0 18 * * *`); the remaining files
are markdown/test fixtures with no runtime cost. Verdict source: the diff adds
a `started_at` field to the existing jobs-API call, two bash global-string
strips, one awk region-slice, and a shared `emit_rows` awk filter — all inside
the existing per-job loop bounded by the 30d / `-L 100` run window.

## 1. Performance summary

- **No new network calls.** `started_at` rides the one REST call per run that
  already existed (`gh api .../jobs?per_page=100`, line 267-271); the
  `gh run view --job --log` count per qualifying job is unchanged (line 281).
  The N+1 profile of the sweep is byte-for-byte preserved — this is the right
  way to obtain the new field.
- **All added work is linear** in the job-log byte count `L`: `${log//$'\r'/}`
  and `${log//$'\357\273\277'/}` are two O(L) in-memory copies (lines 290-291),
  `emit_rows` is O(matched lines), the region-slice awk (lines 307-310) is O(L)
  and early-`exit`s at the bounding `##[group]Run` header, and the trail-pattern
  `grep -qE` (line 317) is O(recovered trail). No O(n²) or worse anywhere;
  bash-level loops iterate only emitted trail lines (small).
- **Recovery is lazy.** The region-slice + emit_rows + grep triple runs only
  when the named anchor yields an empty `trail` (line 305). The common case —
  fresh logs with intact step attribution — pays only the two strips and one
  extra awk fork vs. the old single-awk filter. Correct cost placement.
- **Loop bounds unchanged:** ≤100 completed dispatch runs (exact-cap trips
  CANNOT ESTABLISH, lines 250-253), typically 0-3 `web_host_replace|create`
  jobs per 30d window — replaces are rare manual dispatches.

## 2. Critical issues

None. No P1/P2 findings.

## 3. Measured cost (synthetic 5.8 MB UNKNOWN-STEP log, 15 BOM'd headers,
LC_ALL=C, this host)

Worst-case recovery path per job: **~1.07 s** — BOM+CR strips ~160 ms,
region-slice awk ~0.63 s, emit_rows+grep ~small remainder. A real terraform
apply job log is far smaller; `gh run view --log` itself costs 1-3 s of
network per job, so the added CPU is noise even at the theoretical
100-run × 2-job ceiling (~200 s spread across a sweep already paying ≥200
network round trips). At realistic scale (a few jobs, sub-MB logs) the added
sweep wall-time is tens of milliseconds.

Memory: transient ~2-4× log size (`$log` + each `//` copy + herestring/
command-substitution copies). Same order as the pre-existing code, which
already captured the entire log into a bash variable; bound unchanged.

## 4. Optimization opportunities (P3 — noted, no change requested)

1. **Region-slice regex evaluated on every line** (lines 307-310). The
   `line ~ /^[0-9][0-9TZ:.-]* ##\[group\]Run /` check runs per input line and
   dominates the recovery path (~0.6 s / 5.8 MB). A literal
   `index(line, "##[group]Run")` pre-gate would cut it ~3-5× at pathological
   sizes. Rejected as a required change: the block is deliberately
   `git-data-boot-poll-8178.sh`'s derivation *verbatim*, and drift between the
   two copies costs more than ~0.5 s/job on a daily sweep.
2. **Two unconditional full-string copies per job** (lines 290-291): ~160 ms
   at 5.8 MB combined. Could fold CR+BOM into a single pass via awk, but the
   bash form is 8178's pinned idiom (its comment explains why: one mechanism,
   every consumer of `$log` normalized). Keep.
3. **`emit_rows` is a second fork+scan on the named path** (line 296) vs. the
   old single-awk filter. ~1 extra process + O(matched) scan per job —
   negligible, and the shared chokepoint is the correctness-motivated design
   (one emitted-vs-echoed rule, impossible to drift between two copies).
   Keep.

## 5. Scalability assessment

Projection at 10×/100× load is bounded by construction, not by this diff: the
run list is hard-capped at 100 (cap trips loudly), jobs-per-run is capped by
the `per_page=100` page tripwire, and per-job work is O(log bytes) with gh's
`--log` output as the only input. If the repo ever generates >100 qualifying
dispatch runs in 30d, the probe reads CANNOT ESTABLISH rather than degrading
— correct failure shape. The recovery path cannot amplify: it runs at most
once per job and only on empty `trail`.

## 6. Recommended actions

None required to merge. Observations for the record:

- The suite's `suite-durations.tsv` row stays at the 1200 ms `floor` weight;
  the expanded suite measures ~5 s (69 cases, all passing). The row is a
  shard-balancing weight refreshed by `regenerate-shard-manifest.py`, not a
  gate — no action, but the next regeneration will re-weight it.
- `recovery_cause` grep (line 317) matches the em-dash anchor byte-wise under
  `LC_ALL=C` — consistent with the identical pattern at line 350; fine.

Verdict: **PASS** — 0 P1, 0 P2, 3 P3 optimization notes (all rejected as
required changes; the verbatim-8178 parity is the right trade at daily-sweep
scale).
