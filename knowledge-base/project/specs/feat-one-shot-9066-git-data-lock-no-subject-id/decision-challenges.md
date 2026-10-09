# Decision challenges — feat-one-shot-9066-git-data-lock-no-subject-id

## DC-1 (User-Challenge) — no PR1 payload change: the constant-name lock is already on main

- **Operator direction:** "this PR is PR1 (the payload change, with whatever hash/trigger bookkeeping that sequence requires); do NOT do the PR2 step."
- **What the plan found:** `git-data-remove.sh` and `git-data-provision.sh` on `origin/main` already open `${REPO_ROOT}/.init.lock` (PR #9226, a96d123938, 2026-09-30), and the rung-2 evidence for that exact payload landed in PR #9254 (`RUNG2_TEMPLATE_SHA256` equals the current computed hash, 90b2e7af…74ba). The two-PR sequence has already run for this change.
- **Plan's deviation:** edit no hash-bound file and do not delete the evidence file. A payload edit (even comment-only) would void the evidence and HOLD every git-data birth and replace for a zero-behavior change. Requirement 1 is delivered as a verification record plus a test-only guard for the property; requirement 3 as docs.
- **Default if the operator disagrees:** the operator's direction wins; the alternative is a deliberate payload edit with the evidence deleted in the same PR, followed by `git-data-rung2-rehearsal.yml` on main and an evidence-only PR (the runbook's "Changing the payload: the two-PR sequence"). Nothing in this plan blocks that.
- **Reversibility:** high. Nothing here touches a bound file; a later payload PR is independent.

## DC-2 (Taste) — Art. 30 PA-36 (f) marker in scope

- The CLO consult recommends the same retention wording in ADR-239, the runbook, the ledger and PA-36 (f). The brief named only ADR-239 and the runbook. The plan adds the PA-36 (f) append-only marker (CLO-attested) and leaves the ledger untouched (it already carries `expires_on: 2026-10-22`). Drop the marker if the owner wants strictly the two named docs.

## DC-3 (Taste) — plan-review cuts not taken

- DHH and code-simplicity proposed cutting the runbook step (d) qualifier and the separate `decision-challenges.md`. Kept: the step (d) text is the Art. 17 discharge procedure and is stated in the present tense about wrapper behavior that changes at the next replace (one sentence); `decision-challenges.md` is the sanctioned channel `ship` renders into the PR body. Taken: C4 `model.c4` clause cut, #9066 issue comment cut, mutation rows M5/H3 cut, committed predicate negative control added.

## DC-4 (User-Challenge) — a second id-bearing file exists and is NOT fixed here (found at review)

- **Finding:** `git-data-gc.sh` writes the last completed repo's basename (`<id>.git`) to `.gc-cursor` at the mount root, above the repo root the new check scans. After an erasure the id can persist there until a later run completes a repo (nominally weekly; the freeze stops the timer), indefinitely if no repo remains. Confirmed by two review seats and read in the code.
- **Why not fixed in this PR:** closing it edits a hash-bound payload (`git-data-gc.sh`, or the remove wrapper), which needs the rung-2 two-PR sequence. The scope given for this PR excludes any payload change and the PR2 step.
- **What this PR does instead:** states the limb in ADR-239, the runbook `not covered:` line and the PR body, and records it on #9066 (the open tracker). The owner decides whether to take the payload change before the first flip.
- **Reversibility:** high; nothing here forecloses the fix.

