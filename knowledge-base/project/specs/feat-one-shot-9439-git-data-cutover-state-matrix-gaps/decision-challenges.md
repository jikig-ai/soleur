# Decision challenges — feat-one-shot-9439-git-data-cutover-state-matrix-gaps

## 2026-10-09 — item 8 (failed gc timer restart): fatal everywhere, but never an unwind (superseded by the CTO ruling at review)

- Operator's stated direction: item 8, "A failed `gc.timer` restart only warns."
- Plan default (superseded): `mode_unfreeze` fails (exit 5) and, in a flip, the failed unfreeze step triggered the total unwind. Three review seats (user-impact, data-integrity, security) showed that unwound a PROVEN flip through a writable-store window (writes accepted while the fleet still serves flag=true, orphaned after flag-off), repeated on a standing cause (`gc_timer=unarmed` at boot is tolerated), and in a rollback silently skipped the erasure probe.
- Ruling taken (CTO agent, binding): item 8 stays fatal in every mode, but a timer-only failure does not unwind a proven flip. The verb exits 6; the unfreeze step goes red; the probe and the stamp key on "sentinel cleared"; the finalizer never unwinds for it and never reports it as a freeze; notify carries a distinct `GC_TIMER_STOPPED` word (one new job output, justified because the flip-concluded path exits green and no existing word would fire). Rejected: keep-and-document, a finalizer skip without finishing the flip, a warning, a timer pre-flight in freeze (turns a tolerated boot hygiene fault into a cutover blocker).
- Accepted: the cutover stamp is written with gc stopped (the stamp anchors data location, which gc does not affect); the run is red and notify pages.
- Not fixed here, tracked in the follow-up tracker filed at ship (number in the PR body): a probe or stamp failure after the sentinel clear still unwinds through the same writable window (pre-existing, needs a probe variant that tolerates a same-lineage sentinel or a finalizer re-freeze).

## 2026-10-09 — plan: item 6's marker may page on a write that never landed

- A flip whose flag write fails with a bad token now makes the unwind attempt the flag-off write, fail, and page `RECOVERY_FAILED` ("flag state unknown"). Truthful but noisy. A read-before-unwind refinement was not taken.

## 2026-10-09 — plan: flip resume arm B never unwinds the flag

- Not fixed here: a failed arm-B redeploy leaves the flag true. Fixing it (touch the attempted marker when `resume == arm_b`) changes what a failed resume does to the flag. Filed as its own issue at ship for the owner's decision.
