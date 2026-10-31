---
module: System
date: 2026-10-31
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Issue #11678 proposed raising max_entries_to_merge to shorten queue dwell, but the knob batches merge LANDINGS not merge_group builds — the dwell was build-slot-bound"
  - "The issue's own constraint list omitted the load-bearing one: ADR-270's raise checklist makes CLA group enumeration a precondition, and a safety pin asserts the value ==1"
  - "A first-pass GraphQL query used Terraform parameter names (groupingStrategy, checkResponseTimeoutMinutes, entryCount); the live schema names differ (mergingStrategy, checkResponseTimeout, no entryCount)"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: low
tags: [merge-queue, brainstorm, premise-validation, graphql, adr-270]
---

# Learning: verify a platform knob's semantics before scoping the issue that tunes it

## Problem

Issue #11678 framed `max_entries_to_merge` as the fix for serial queue dwell
("queued PRs merge as a group under one `merge_group` run instead of N serial
runs"). The frame was wrong in the load-bearing place: GitHub documents verbatim
that *"Merge limits do not combine `merge_group` builds. Merge limits only
affect merges to the base branch once one or more `merge_group` has satisfied
build checks."* Under `ALLGREEN`, each queued PR still pays its own ~50-min
cumulative candidate build — #11646's 3h53m dwell (armed 15:24Z → enqueued
17:00Z → merged 20:53Z, verified via GraphQL timeline) was build-slot-bound
(`max_entries_to_build = 2`, the issue's own non-goal). A's true win is
post-merge amortization, not wait reduction.

The same issue's "constraints discovered in-tree" list missed the constraint
that actually gates the change: ADR-270's raise checklist (CLA enumeration,
Guard-2 safety pin `==1`, timeout re-derivation, parity sweep) and the
`merge-queue-cla-verify.sh` single-PR `head_ref` regex that fails closed on any
batched group.

## Solution

- Verify knob semantics against platform docs BEFORE the leader fan-out
  settles the value model: one WebFetch of the merge-queue docs corrected the
  whole cost/benefit framing.
- Grep the governing ADR for the change's own name (`Raise checklist`) — the
  checklist already enumerated the preconditions the issue missed.
- Pull the issue's motivating datapoint's timeline via GraphQL — attribution
  (pre-enqueue CI vs queue-position wait vs builds) decided which lever
  actually helps.
- Introspect `__type(name:"MergeQueueConfiguration")` before querying — schema
  field names (`mergingStrategy`, `checkResponseTimeout`, no `entryCount`)
  differ from the Terraform parameter names.

## Key Insight

An issue that proposes tuning a named knob carries an implicit claim about
what that knob DOES. Verifying the knob's documented semantics costs one doc
fetch and can re-scope the whole brainstorm — in this case it moved the
queue-dwell fix off Proposal A entirely and reframed A as post-merge
amortization. Companion: the issue's in-tree constraint list is the author's
reading history, not the constraint set — grep the governing ADR for the
knob's own checklist before treating the list as complete.

## Session Errors

1. `SOLEUR_FEATURE_PUSH_FAILED` — worktree-manager created the branch but its
   push failed; manual `git push -u origin` succeeded.
   **Prevention:** none needed — transient, and the script already prints the
   remediation. Noted as a flake class.
2. GraphQL schema errors on first `mergeQueue` query (tf-style names;
   `entryCount` nonexistent).
   **Prevention:** introspect `__type` before writing queries against a
   schema whose field names only resemble the IaC parameter names; keep the
   verified field list in the artifact (spec §Observed Values).

## Tags
category: workflow-patterns
module: merge-queue
