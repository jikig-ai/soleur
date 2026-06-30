---
date: 2026-06-30
category: workflow-patterns
tags: [premise-validation, inngest-cron, scope-reduction, deepen-plan, process-substitution, bash]
feature: feat-roadmap-program-layer
pr: 5753
issue: 5755
---

# Premise correction: grep the right automation layer, and let discovered facts drive scope down

## Context

Brainstorm→plan→deepen for a "roadmap program layer" (adapted from mattmccray/plan): a
`product-roadmap validate` drift-check + `next` advisory. The original framing —
*"automate the manual monthly roadmap reconciliation; no cron exists"* — was **stale**, and the
feature shrank ~60% across three review gates as facts surfaced.

## Lesson 1 — Grep the layer where the automation actually lives, not the obvious one

When validating "no automation exists, so build it," an early grep of `.github/workflows/` returned
zero and produced a confident **false-negative** ("no roadmap cron"). The real automation was an
**Inngest** cron at `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` (ADR-033:
Inngest > GitHub Actions is the canonical cron substrate here). It already emitted the exact verdicts
the new skill proposed (`STALE_STATUS`/`MISSING_ISSUE`/`EMPTY_MILESTONE`), ran weekly, and opened a
fix PR. The CPO domain leader's "a cron is already running" was correct; I'd dismissed it because I
grepped the wrong layer.

**What surfaced it:** reading **ADR-054** at plan time (Phase 0.6 premise-validation) — it listed
`cron-roadmap-review.ts` as a permanent `safeCommitAndPr` exemption. **Takeaway:** for "does X
automation exist?", grep BOTH `.github/workflows/scheduled-*.yml` AND
`apps/*/server/inngest/functions/cron-*.ts`, and read the ADR corpus for the mechanism — an
architectural-decision record names the live implementation a workflow grep misses.

## Lesson 2 — Three fact-driven scope reductions are convergence, not thrashing

Each reduction was forced by a discovered fact and made the feature **smaller AND safer**:
1. **Consolidate, not duplicate** (cron already reconciles) → don't build a duplicate + new GHA cron.
2. **`next` advisory, not a driver** (Phase 4's open work is recruitment/interviews — *non-codeable*)
   → report the next action; never auto-hand to `/soleur:one-shot`, which would mis-direct a
   non-technical founder at engineering.
3. **Drop the `--apply` write path** (deepen-plan: 3 reviewers converged that the write path was all
   risk, no capability the cron's reviewed-PR write didn't already provide) → `validate` is
   report-only; threshold dropped single-user-incident → low; ADR-070 + the bounded-region migration
   + 5 write-safety holes all dissolved.

Each "smaller" was a correctness win, not a cut corner. Honest end-state: **`validate` reads, the
cron writes-via-PR.**

## Lesson 3 — Process-substitution FIFOs drain on first read

`reconcile_counts <(roadmap) <(milestones)` re-ran `jq "$milestones_file"` once per phase-row in a
loop. A `<(...)` file is a FIFO that **drains on first read**, so iterations 2+ saw empty input and
spuriously emitted `MISSING_ISSUE` for every phase after the first. RED tests (TS2/TS3) caught it.
**Fix:** slurp the file once into a variable (`ms_json="$(cat "$milestones_file")"`) and feed `jq`
via `<<< "$ms_json"`. Any bash function that reads a passed-in file path more than once must slurp
first — the caller may hand it a FIFO.

## Also

- An advisory classifier should **under-classify to the safe side**: a too-broad codeable-label set
  ( `type/chore`) labeled "Launch on Product Hunt" as codeable. Narrowing to engineering-only labels
  makes the tool name it as an operator action rather than wrongly tell the founder to build it.
