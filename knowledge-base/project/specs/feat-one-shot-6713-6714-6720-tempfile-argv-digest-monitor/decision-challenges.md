# Decision Challenges — feat-one-shot-6713-6714-6720

Recorded headless (one-shot pipeline; no operator prompt per the plan-review headless arm).
`/ship` renders these into the PR body and files an `action-required` issue.

## DC-1 — Marker 4 (`SOLEUR_CRON_TIER2_DEFERRED`) retained against review recommendation

**Class:** taste (scope)
**Reviewer:** code-simplicity-reviewer, plan-review
**Recommendation:** cut. `TIER2_DEFERRED_CRONS` is empty at HEAD (`_cron-shared.ts:736`), so the
marker instruments a condition that is not currently occurring — "textbook just-in-case."

**Decision: retained.** Two reasons the plan judges decisive:
1. The Tier-2 defer path **posts a GREEN Sentry check-in while committing nothing**
   (`_cron-shared.ts:745-750`). That is exactly the class ADR-126 generalizes — "every GREEN
   check-in path must be enumerated." Cutting the marker would contradict the ADR the same PR
   writes.
2. It is not hypothetical: the defer accounted for **4 of the 41 gap days** (H3, CONFIRMED), and
   it was indistinguishable from a healthy run at the time — which is why those 4 days took
   archaeology to explain.

Cost is one emit line at one site. The reviewer's YAGNI logic is sound in general; the plan
judges the ADR-consistency argument to outweigh it here.

**If the operator disagrees:** cut marker 4 and its Test Scenario 11, and add a sentence to
ADR-126 noting the defer path is a known-unenumerated GREEN check-in.

## Accepted without challenge

All other plan-review findings were accepted and applied: Phase 0 cut (duplicated ACs); Phase 1.4
fold-ins cut to a tracked sweep issue; Phase 1.5 new test file cut in favour of cases in the
already-wired freeze suite (the reviewer found it would have been unreachable — a real defect);
`DM_MAX_FACTS` cut (invented failure mode); marker 6 cut (duplicate of marker 2's
`reason=timeout`); three AC cross-reference/coverage defects corrected.
