---
title: A count-drift fix must sweep sibling non-test-gated docs, not just the gate that reds
date: 2026-07-18
category: best-practices
tags: [drift, documentation, review, scope, observability, c4]
issue: 6644
pr: 6647
---

# Learning: fixing a drifted count in the file that reds CI is necessary but not sufficient — the same root cause left the count stale in a sibling doc that no gate watches

## Problem

Issue #6644 was a single stale factual count: `model.c4`'s `github -> sentry` edge
description said "Of 49 cron monitors" while `apps/web-platform/infra/sentry/cron-monitors.tf`
declares 50 (PR #6632 added `scheduled_heartbeat_reconcile` and left the diagram behind).
The drift reds `scan-workflow.test.sh` under `bash -e` in the `deploy-script-tests` job,
which halts every later-registered infra guard. The plan scoped the fix to the two artifacts
the two CI gates watch: `model.c4` (scan gate) + its compiled twin `model.likec4.json`
(freshness gate). Both green after the fix.

But the SAME monitor addition left the SAME count stale in a **non-test-gated** sibling:
`apps/web-platform/infra/sentry/README.md:16` ("**49 cron monitors**"), sitting one directory
above the `cron-monitors.tf` that is the source of truth. No gate reds on it, so the plan's
cross-artifact classification (which correctly triaged `model.c4`, `model.likec4.json`,
`cost-model.md`, and historical audit/brainstorm records) never surfaced it. It was caught
only by a review-phase `grep -rn 'cron monitors'` across `apps/`.

## Solution

Fix inline (1 line, 1 file — cost-of-filing gate mandates inline, not a follow-up issue):
`README.md:16` 49 → 50. Committed with a `review:` prefix as a same-root-cause P3.

Discriminate same-metric drift from different-metric coincidence: `cost-model.md:314` and
`expenses.md` also say "49", but those are **billing-seat** figures (50 monitors − 1 reserved
= 49 PAYG seats) — a distinct metric, correctly left unchanged. The monitor **count** (README,
model.c4) is what tracks the tf resource count; the **seat** count does not.

## Key Insight

When a fix corrects a drifted count in the artifact that reds a gate, the drift almost always
has siblings the gate does not watch:

1. **Enumerate every current doc that states the same semantic quantity**, then grep per-figure
   (`grep -rn '<metric phrase>' <dirs>`). The gate names one file; the root cause (a resource
   added upstream) touches the whole documentation surface that describes that resource class.
2. **Same directory as the source-of-truth is the highest-signal sibling.** An infra `README.md`
   next to the `.tf` it describes is a current, human-maintained count — not a historical record
   — so it should track, and drifts silently because nothing tests it.
3. **Separate the metric from its coincidental value.** The same integer can appear as two
   different metrics (monitor-count 50 vs billing-seats 49). Sweep by *what the number means*,
   not by the digits. This is the "sweep the semantic quantity, not its formatted representation"
   discipline applied across metrics rather than across formatting.

Cheapest guard: at review time on any count-drift PR, `grep -rn '<metric>' apps/ knowledge-base/`
and classify each hit as (a) same-metric-current → fix, (b) different-metric → leave with a
one-line note, (c) historical point-in-time record → leave.

## Session Errors

Session error inventory: none detected. No skill/path/hook errors, no failed commands, no
backtracking. The one process gap was a **plan-scoping omission** (the infra README sibling),
caught and fixed at the review phase — recurring-class, dispositioned fix-now-inline.

**Prevention:** the review-phase cross-artifact grep above is the mechanical catch; captured
here so the next count-drift fix greps the full doc surface before declaring "two files."

## Tags
category: best-practices
module: observability / infra-docs
