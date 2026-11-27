---
title: A wall-clock p90 breach is three hypotheses — duration_p90 and same-run siblings pick one
date: 2026-11-19
category: best-practices
module: ci, watch-wallclock-p90
tags: [wallclock-p90, bounds-tsv, reseed, bimodal, needs-chain, 12965]
related: ["#12755", "#11556", "#12877", "#12905", "#12965"]
---

# Learning: adjudicate a bound breach by latency shape, not by the breach line

## Problem

`tenant-integration-required` breached its PR wall-clock bound twice in a week
(2026-11-13 ~900s, 2026-11-18 915s vs bound 300×1.30=390). Three hypotheses fit
the same `::error::` line: (a) the bound was mis-seeded for a legal slow mode,
(b) a transient queue tail that will roll off, (c) a genuine regression the
bound exists to catch. Acting on the wrong one is expensive in both directions —
re-seeding (c) silences a real regression; leaving (a) burns the drift watch on
a permanent false positive.

## Solution

The discriminator is two numbers and one sibling comparison, all in the same
`--print-report --dry-run` census:

1. **Per-sample timeline shape.** 23/26 samples at 11–76s and 3 at 915–970s is
   bimodal, not a tail — a bimodal population is one bound over two latency
   classes. The slow samples each sit ~20s after the check's heavy
   `needs`-chain predecessor (the path-gated tenant suite, ~835–910s) finished:
   the latency IS the predecessor, not the check.
2. **`duration_p90` (execution-only).** 21s ≈ fast-mode execution — rules out
   (c) as an aggregator regression in one number. A regression signature would
   raise this, or add an MQ-surface breach, or add failed check-runs reads.
3. **Same-run independent siblings.** Other required checks on the 3 slow runs
   stayed ≤~355s — a shared-queue burst inflates *all* independent checks, so
   their flatline refutes (b). (Name the class precisely: needs-chain
   *umbrella* aggregators like `test`/`quality-guards` DO serialize their own
   legs higher — the discriminator only works on independent legs.)

Then seed per the TSV header contract: **next-minute ceiling of measured p90,
never of max** — the 0.30 margin is designed to absorb the observed max
(960×1.30=1248 > 970); seeding from max double-counts it. And verify the OTHER
surface isn't affected before touching its bound (merge_group skipped the
heavy suite entirely — `tenant=false` — so its 180 bound stayed).

## Key Insight

A single bound over a bimodal population has structurally thin headroom: the
seed sits at the fast-mode ceiling while the slow mode can grow to the
predecessor's own timeout cap. Post-seed the breach line (1248s) only catches
wait-side pathology (~50s over max observable ~1200s) — execution-drift
detection correctly lives in the suite's `timeout-minutes` + the fail-closed
gate, not this ratchet. The structural fix is shrinking the slow mode
(#12905), and any down-seed after it needs a fresh same-method census — the
960 does not survive its predecessor changing.

Also captured: a mid-flight `cancelled` sample is censorable evidence, not a
mechanism — a job *executing* cannot have been killed by the pending-entry
eviction arm (`cancel-in-progress: false` protects it), so the trigger stays
unattributed until a second one lands.

## Session Errors

1. **`pgrep -f` blocked as self-matching** — one-off harness constraint.
   **Prevention:** use `kill -0 <pid>` on a captured PID or `proc.sh`'s
   `list_runs`/`kill_mine` helpers.
2. **`gh issue view` timed out twice before succeeding** — transient flake.
   **Prevention:** wrap `gh` reads in `timeout`; they have no request-timeout
   flag of their own.
3. **First measurement run raced the TSV edit** — launched before the row
   edit landed, so it reported against bound=300. Recovered by re-running
   post-edit. **Prevention:** if the edit feeds the report's bound column,
   land the edit before launching the ~4-min probe; if only the p90 values
   matter, order is immaterial.
4. **Review seat returned empty output** — respawn with an explicit
   "final message IS the deliverable, never end on a status line" clause
   returned a substantive report. **Prevention:** carry that clause in every
   spawn prompt, not only on resume.
5. **`session-state.md` kept pre-CTO wording** — the correction sweep fixed
   plan/runbook/decision-challenges but missed the narrative artifact
   (`≤478s`, "mutex eviction" attribution). **Prevention:** already covered —
   sweep by the claim's SUBJECT (every mention of the corrected figure), not
   by file list; review caught it, fixed inline.
6. **Coverage trailer emitted before all seats confirmed substantive** —
   degraded 3/4 trailer then needed a manual supersede commit.
   **Prevention:** verify every spawned seat's output is substantive BEFORE
   `emit-review-trailer.sh`; the script is idempotent, so a late seat costs a
   supersede commit.

## Prevention

- For any future bounds-TSV breach: run the three-discriminator check above
  before choosing re-seed vs investigate vs file-regression.
- For the corpus: the slow-mode samples' lag after predecessor `completed_at`
  (+19..+22s) is the fingerprint that the latency is a needs-chain wait, not
  queue time — check it before attributing a tail to congestion.
