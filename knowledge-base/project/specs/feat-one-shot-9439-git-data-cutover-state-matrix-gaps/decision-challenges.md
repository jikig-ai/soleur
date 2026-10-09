# Decision challenges — feat-one-shot-9439-git-data-cutover-state-matrix-gaps

## 2026-10-09 — plan: item 8 (failed gc timer restart) is fatal

- Operator's stated direction: item 8, "A failed `gc.timer` restart only warns."
- Taste call: the plan makes `mode_unfreeze` fail (exit 5, `gc_timer_restart_failed`). In a flip that fails the unfreeze step and triggers the total unwind (flag off, redeploy), and the finalizer's own unfreeze retry will usually fail the same way, ending in `RECOVERY_FAILED`.
- Alternative: fatal for rollback and standalone `mode=unfreeze`, but red-without-unwind for flip (needs a finalizer marker).
- Default taken: fatal everywhere after one immediate (no-sleep) retry, cost stated in the runbook (including that a rollback with this failure also skips its erasure probe). Reverse by choosing the alternative in a follow-up.

## 2026-10-09 — plan: item 6's marker may page on a write that never landed

- A flip whose flag write fails with a bad token now makes the unwind attempt the flag-off write, fail, and page `RECOVERY_FAILED` ("flag state unknown"). Truthful but noisy. A read-before-unwind refinement was not taken.

## 2026-10-09 — plan: flip resume arm B never unwinds the flag

- Not fixed here: a failed arm-B redeploy leaves the flag true. Fixing it (touch the attempted marker when `resume == arm_b`) changes what a failed resume does to the flag. Filed as its own issue at ship for the owner's decision.
