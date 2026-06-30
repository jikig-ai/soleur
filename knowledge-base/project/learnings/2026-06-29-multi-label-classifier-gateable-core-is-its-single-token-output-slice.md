---
title: A multi-label classifier's gateable core is its single-token output slice
date: 2026-06-29
category: best-practices
tags: [eval-harness, classifier-gate, multi-label, single-token, brainstorm-scoping, pdr, lane-inference]
module: eval-harness, brainstorm, classifiers
related-issues: [#5704, #5722, #5702, #5701]
related-learnings:
  - knowledge-base/project/learnings/2026-05-15-classifier-prose-table-row-ordering-collision.md
related-brainstorm: knowledge-base/project/brainstorms/2026-06-29-expand-gated-skill-catalog-brainstorm.md
---

# Learning: A multi-label classifier's gateable core is its single-token output slice

## Problem

Issue #5704 asked to expand the eval-harness validation gate (single-token-label only) to
"additional classifier-like surfaces, e.g. `pdr-*` passive domain routing." Taken literally,
`pdr-*` is a poor fit: passive-domain-routing decides *which set of domain leaders to spawn* —
genuinely multi-label (one message can route to two domains for distinct asks). The harness
asserts only single-token labels; the README defers non-single-token surfaces to a future
set-membership assert. So the named example looked like it forced either a net-new assert
script or constraining golden tasks to single-signal cases (which skips pdr's hard case and
gives false confidence).

## Solution

Don't gate the multi-label decision; gate its **single-token output slice**. Passive-domain
routing has two separable outputs:

- *breadth* — how many leaders (`procedural` / `single-domain` / `cross-domain`): a clean,
  frozen, single-token enum, surfaced as brainstorm **lane-inference**.
- *identity* — which specific leaders: irreducibly multi-label.

Gating lane-inference brings the verifiable slice of pdr under the gate with zero new code
(reuse the additive recipe), and defers only the identity slice (filed as #5722). The scope
chosen — lane-inference + skill-security-scan, defer pdr — satisfies #5704's intent honestly
without half-covering the multi-label part.

## Key Insight

**When an issue names a multi-label surface as a gate/eval candidate, look for a single-token
projection of its output before deciding between (a) building a set-membership assert or
(b) constraining tasks to fit.** Many "multi-label" classifiers are a single-token decision
(a count, a tier, a breadth) composed with a multi-label decision (a set). The single-token
factor is cheap to gate now and usually captures most of the regression risk; the set factor
can be deferred whole rather than half-covered. Half-covering a multi-label surface with a
single-label harness is worse than deferring it — it ships false confidence.

Corollary (carried from #3785): golden sets for *routing* classifiers must include adversarial
keyword-overlap tasks (a message matching two labels), because cross-label collisions are
exactly the regressions a routing gate exists to catch — and they only surface if the corpus
contains overlapping-signal tasks.

## Session Errors

1. **`Monitor` tool invoked without its schema loaded** — passed a `timeout` param the
   client-side parser rejected (`InputValidationError`; the tool was a deferred tool whose
   schema must be fetched via `ToolSearch` first). Recovery: the call was unnecessary — the two
   background agents auto-notified on completion, so I proceeded on the notifications.
   Prevention: don't poll background agents with `Monitor`; harness-tracked agents re-invoke
   the caller on completion. If a deferred tool is genuinely needed, `ToolSearch
   select:<name>` first.

## Tags
category: best-practices
module: eval-harness, brainstorm, classifiers
