# Decision Challenges — feat-one-shot-7652-fixture-dir-assert-boundary-scope

Surfaced by `plan-review`, not auto-applied. Each entry challenges the operator's stated direction,
so per ADR-084 it is recorded here for the operator to decide rather than silently applied.

## UC-1 — Split #7652 into two PRs

**Operator's stated direction (the default).** One PR, closing #7652, carrying both instances the
issue filed together.

**What the reviewers said.** Three of eight consults independently recommended splitting: the
boundary widening (detection) and the operand/CWD work (prevention) are separable, and the plan
itself notes the boundary work is independently shippable.

**Why they argued for it.**
- The two halves have different risk profiles. Prevention introduces no new exposure; detection
  introduces the credential-disclosure surface (R2) and the false-accusation surface (R3). Those
  should not ride into main on the urgency of the fix they are not delivering.
- Review load: one PR would carry two mechanisms, three guard contracts and ~15 acceptance criteria.
  Nobody holds both halves in their head, so nobody reviews either.
- **The strongest argument, and it inverts the obvious order:** the boundary *is* the detector for
  this family. Landing it first means it is live and watching while the second PR edits fixture
  suites en masse — precisely the window in which a fixture change is most likely to write to the
  live repository. Bundling them means the detector arrives only after the riskiest editing is done.

**Recommended shape if accepted.** PR-A = the boundary (Phases 0 + 2), `Refs #7652`. PR-B = CWD
isolation, the residual assertion and the scanner (Phases 1 + 3 + 4), `Closes #7652`. Only PR-B
carries the closing keyword, so #7652 is not closed while half of it is unfixed.

**Why it was not applied.** It changes operator-stated scope, which is never a Mechanical class.
The plan is written so either path works: the phase order already puts the boundary first, and
Phase 0 step 7's observe-only full run is the gate on whether the boundary half is safe to ship
before the sites are fixed.

**Decision:** _pending operator_
