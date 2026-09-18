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
