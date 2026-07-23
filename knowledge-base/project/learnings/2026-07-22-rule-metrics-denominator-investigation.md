---
title: "rule-metrics denominator investigation — do not prune on `rules_unused_over_8w` yet (#6794)"
date: 2026-07-22
issue: 6794
tags: [rule-metrics, governance, telemetry, agents-md]
category: investigation
---

# rule-metrics denominator investigation (#6794, item 1)

**Decision: do NOT scope or run a rule-pruning campaign now.** The
`rules_unused_over_8w` figure is not yet an actionable pruning mandate — for a
different reason than #6461's originating issue assumed. Re-evaluation trigger:
**before any PR that retires rules in bulk.**

## What #6461 / #6794 asked

`knowledge-base/project/rule-metrics.json`'s `.summary.rules_unused_over_8w`
field is **volatile across regenerations** — observed at `98` (the #6794 body),
`101`, and `94` on successive machine-local aggregate runs within days, against a
stable `total_rules_tagged: 101`. That the committed figure swings ~93–100%
between runs, with no rule set change, is itself the first evidence that it is
not measuring a stable "dead-weight" property. #6461's originating issue read an
earlier figure as "98 of **198**", a category error. #6794 asked two questions
before acting: (1) is the denominator right, and (2) is the "unused" signal real
or a telemetry artifact?

## Finding 1 — the denominator is 101, and `202` is a 2×101 double-count

Re-derived two independent ways (per the "re-derive numerator AND denominator
two ways" discipline):

- **Method A (grep the source):** `AGENTS.md` carries **101** `- [id: …]` index
  pointers; the sidecar bodies sum to **101** (`AGENTS.core.md` 53 +
  `AGENTS.rest.md` 42 + `AGENTS.docs.md` 6). `lint-rule-ids.py` couples each
  pointer to exactly one body.
- **Method B (the artifact):** `rule-metrics.json .summary.total_rules_tagged` =
  **101**.

So `202` = **2 × 101** id-*occurrences* (one index pointer + one sidecar body per
rule), NOT "101 tagged + 101 untagged". There is no untagged population. The
aggregate parses only `AGENTS.md`'s 101 pointers and correctly uses **101** as
the denominator. **The denominator is not the problem.**

## Finding 2 — telemetry IS being recorded, but the aggregate under-counts it structurally

The naive hypothesis ("~0 events ⇒ telemetry-absence ⇒ the unused rate is an
artifact") is **falsified at the source level**. Unioning every worktree's
`.claude/.rule-incidents.jsonl` (machine-local, per-checkout; the bare mirror
excluded per `hr-when-in-a-worktree-never-read-from-bare`):

- **~1191 rule events** over **2026-07-06 → 2026-07-22 (~16 days ≈ 2.3 weeks)** →
  **~520 events/week**. Telemetry is being written at a healthy rate.
- **BUT only 21 distinct `rule_id`s** appear across all 1191 events. 80 of the
  101 tagged rules did not fire in the window.

The catch is **how the aggregate reads the data**. `rule-metrics-aggregate.sh`
reads only the *single* per-checkout `$REPO_ROOT/.claude/.rule-incidents.jsonl`
(ADR-091 names `compound` the authoritative local producer; #6042 documents the
per-checkout no-op path). Sessions run in *separate worktrees*, each with its own
`.claude/`, so any single checkout — and especially a fresh one — sees a tiny
slice or none of the 1191 events. **The committed `98–101/101 unused` reflects
one near-empty checkout's log, not the union.** It is a fragmentation
under-count, not a measurement of dead weight.

## Why "do not prune now"

Two independent reasons, either sufficient:

1. **The as-recorded metric is not trustworthy for pruning.** It is computed
   per-checkout over fragmented, machine-local logs; it systematically
   under-counts fires. A bulk prune keyed to `rules_unused_over_8w` would retire
   rules that *have* fired in sibling sessions the aggregate never read.
2. **Even a unified count is not yet a mandate.** The union spans ~2.3 weeks —
   far short of the 8-week (56-day) window the field name (`_over_8w`) implies.
   And "unused in window" ≠ "dead weight": a rule that fires only when a rare,
   costly mistake is imminent is doing its job precisely by rarely triggering.
   Retiring on short-window silence optimizes for the wrong thing.

## What would make it actionable (re-eval trigger = before any bulk-prune PR)

- Fix the aggregation to union across all session logs (or centralize the
  telemetry), so the denominator's numerator is the *real* fire history — not one
  checkout's slice.
- Then observe over a genuine ≥8-week window.
- Only then scope a pruning campaign, and even then weigh rare-but-load-bearing
  guards individually rather than by a blanket unused-in-window cut.

Related: [[2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim]].
