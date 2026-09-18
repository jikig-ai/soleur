# Decision challenges — feat-one-shot-7695-recut-postcutover-reconcile

Taste findings from plan-review (headless run, 2026-09-18) that were NOT auto-applied. Rendered by
`/ship` Phase 6 into the PR body and filed as `action-required` if any needs an operator call.

## T1 — DHH: trim `## Research Insights` to ~5 bullets

**decisionClass:** taste. **Not applied.** The plan skill mandates the section (Premise Validation,
Property List, Cut List are what `plan-review` reads), and the guard re-grade table is the evidence
the issue closures cite. Cost: ~180 lines of plan prose nobody must read to implement.

## T2 — DHH: drop `measurements.md`; put the re-read into the #7695 closing comment

**decisionClass:** taste. **Not applied.** The scoped advisor consult asked that closing comments
quote a committed measurement file rather than plan-time values; the file is also the Phase 0.1 STOP
gate's record. If the operator prefers comment-only, delete Files-to-Create bullet 1 and AC9.

## Applied at plan time (for the record)

Both panels fired on spec-flow's exit-5 follow-through probe → deleted (delete over fix). No
User-Challenge: the operator's stated scope (reconcile, close/re-scope with evidence, no destructive
dispatch, disjoint from PR 8248, no cloud-init edit) is unchanged.

## Review-time (2026-09-18) — code-simplicity-reviewer: trim the G3.7 callout to a pointer at ADR-100

**Finding:** the runbook callout restates ~40% of the ADR-100 addendum (guard-by-guard verdicts, run/host ids,
host count, #6894/ADR-142/#8316 fate); replace with one clause + "verdicts in ADR-100 addendum 2026-09-18".

**Disposition: applied in part, declined in part (taste, user-legible).** Applied: the P1-13 blockquote no longer
restates G1/G3.7; ADR-100's "never dispatched" names its read; the replace-survival claim is anchored on
`inngest-host-replace`. Declined: the callout keeps G19/G8/G9/G13, the measured row values and the run/host ids
because AC2 (CTO domain review: "the callout must lead with G19"; deepen's observability-coverage pass: "every
value names its read and layer") is the plan's contract for the mid-incident reader — an engineer on the `done`
host reads the runbook, not the ADR, and `hr-no-dashboard-eyeball-pull-data-yourself` wants the read command
beside the value. The re-measure line bounds staleness of the host id. Operator's stated direction unchanged.
