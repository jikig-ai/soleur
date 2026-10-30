---
title: "Verification scaffolding carries the defect"
summary: "In guard-shaped fixes, review finds defects in the tests and batteries rather than the fix, because verification inherits the old bug's framing; it needs its own adversarial pass."
status: open
opened_on: "2026-10-24"
tags: [review, guards, verification, vacuity]
evidence:
  - knowledge-base/project/learnings/2026-09-04-every-defect-the-panel-found-was-in-my-verification-not-my-fix.md
  - knowledge-base/project/learnings/2026-09-04-every-defect-this-session-was-in-the-verification-not-the-fix.md
  - knowledge-base/project/learnings/2026-09-03-every-p1-was-in-the-verification-not-the-fix.md
  - knowledge-base/project/learnings/2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md
  - knowledge-base/project/learnings/2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md
required_reading: false
---
## Root cause

A fix is written while holding the old bug in mind, so its tests and batteries pin the shape of that
bug rather than the property, and they are written fast because they feel like bookkeeping. The
guard and the thing it guards often share a failure mode: a vacuity floor enforced through the
function it must survive, a gate satisfied by deleting what it guards, a verdict counter that is
direction-blind. Each review round's fix then introduces the next round's defect.

## Fix

Treat the verification as a deliverable with its own review: ask of every floor what its unit is and
whether the unit can stay constant while discrimination drops to zero, route the floor's failure
exit around the assertion machinery, keep an append-only verdict ledger instead of conserved totals,
and re-measure after every fix round. Instruments with disjoint yields are combined rather than
trusting one.

## Evidence

- knowledge-base/project/learnings/2026-09-04-every-defect-the-panel-found-was-in-my-verification-not-my-fix.md
- knowledge-base/project/learnings/2026-09-04-every-defect-this-session-was-in-the-verification-not-the-fix.md
- knowledge-base/project/learnings/2026-09-03-every-p1-was-in-the-verification-not-the-fix.md
- knowledge-base/project/learnings/2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md
- knowledge-base/project/learnings/2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md
