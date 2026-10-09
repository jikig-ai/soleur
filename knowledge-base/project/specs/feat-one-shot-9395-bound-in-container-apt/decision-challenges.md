# Decision challenges: feat-one-shot-9395-bound-in-container-apt

## 2026-10-08 plan-review (headless, taste class)

1. **Population census in A10 (kept, minimal).** The code-simplicity seat said cut it (no ask maps to it; a future false-positive surface) and defer to a follow-up; the DHH seat said keep it as about eight lines inside A10 with no dedicated matrix. The plan keeps it at that size because the guard-contract gate requires a structural, tree-derived assembly rather than a hand-listed consumer set. If the census proves noisy, deleting it is a few lines.
2. **Tier B non-decline build failure becomes a counted FAIL (was: any failure skipped).** Follows the helper's contract (rc 97/98/137 must never read as the decline), but it changes CI behaviour for pull stalls or rate limits that used to be a quiet skip, and the current skip rate by cause was not measured. Only docker rc 125 and the apt decline remain skips.
3. **Cutover budget 270 s (ownership uses 180 s).** Sized to survive two capped 90 s stalls plus a healthy 55 s cycle because the arm fails closed under CI on a decline (#8744). The alternative is the ownership precedent of 180 s with a higher chance of a fail-closed red on a slow-mirror day.
