# Decision Challenges — feat-one-shot-6713-6714-6720

Recorded headless (one-shot pipeline; no operator prompt per the plan-review headless arm).
`/ship` renders these into the PR body and files an `action-required` issue.

## DC-1 — Marker 4 (`SOLEUR_CRON_TIER2_DEFERRED`) retained against review recommendation

**Class:** taste (scope)
**Reviewer:** code-simplicity-reviewer, plan-review
**Recommendation:** cut. `TIER2_DEFERRED_CRONS` is empty at HEAD (`_cron-shared.ts:736`), so the
marker instruments a condition that is not currently occurring — "textbook just-in-case."

**Decision: retained — but the original reasoning was wrong and is corrected here.**

Post-implementation review (`code-simplicity-reviewer`, independently) dismantled both arguments the
plan originally gave, and it was right to:

1. ~~"Cutting it would contradict the ADR the same PR writes."~~ **Circular.** ADR-126 is an artifact
   of *this* diff; a document being authored here cannot be an external constraint on it. The tell
   was that the ADR clause had to carry a defensive parenthetical apologising that the instrumented
   condition does not occur.
2. ~~"It accounted for 4 of the 41 gap days."~~ **Backward-looking and irrelevant.** Those days were
   2026-06-09 → 06-12; the marker did not exist then and would not have helped. It helps only if
   `TIER2_DEFERRED_CRONS` is ever repopulated — a hypothetical future, which is precisely what YAGNI
   targets. The branch is genuinely unreachable at HEAD.

**The argument that actually holds** (which the plan did not make): `deferIfTier2Cron` is not
speculative code this PR introduced. It is a live exported function called from 8 cohort handlers,
which a *prior* decision deliberately retained as a defensive no-op. YAGNI polices speculative paths
you add; it does not police instrumentation on a branch someone already decided to keep. Cutting the
marker while keeping the branch is the internally inconsistent position — it says the branch is
worth preserving against a future repopulation but the one line telling you it fired is not. And if
the set is repopulated, whoever does it will not remember to add the marker, so the blind spot costs
archaeology a second time.

Cost is one emit line at one site.

**If the operator disagrees:** cut marker 4 and its Test Scenario 11, and add a sentence to ADR-126
noting the defer path is a known-unenumerated GREEN check-in.

## Accepted without challenge

All other plan-review findings were accepted and applied: Phase 0 cut (duplicated ACs); Phase 1.4
fold-ins cut to a tracked sweep issue; Phase 1.5 new test file cut in favour of cases in the
already-wired freeze suite (the reviewer found it would have been unreachable — a real defect);
`DM_MAX_FACTS` cut (invented failure mode); marker 6 cut (duplicate of marker 2's
`reason=timeout`); three AC cross-reference/coverage defects corrected.
