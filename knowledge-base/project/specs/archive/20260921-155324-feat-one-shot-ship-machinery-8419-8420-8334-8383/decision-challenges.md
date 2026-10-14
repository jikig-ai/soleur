# Decision challenges — feat-one-shot-ship-machinery-8419-8420-8334-8383

Recorded headless by `soleur:plan` plan-review (2026-09-21). These are judgment calls made without
the operator; `ship` renders them into the PR body.

## Taste — settle-then-admin-merge hatch not extracted (was an issue-listed candidate)

- **Issue text:** #8419 and #8438 both name the ship Phase 7 settle-then-admin-merge hatch as a
  top extraction candidate.
- **Decision:** not extracted. The BEHIND-arm consolidation alone frees about 5.4 KB, which clears
  the 4 KB floor. The hatch's sync-2 trigger also appears in no line the poll prints, so moving the
  procedure out would leave it loaded only if the agent remembered it.
- **Contingency:** if the measured headroom falls short, the hatch is extracted and the poll prints
  a `hatch_check` line at the second sync.
- **Cost of the other choice:** about 11 KB more headroom now, at the risk of the procedure not
  being loaded when it is needed.

## Taste — CTO devex recommendations not applied

- **Plugin-cache `find` fallback for the sync script path:** not applied. A search over paths the
  customer's machine controls brings back the risk ADR-179 closes. Shells that have no plugin root
  lose auto-sync and say so.
- **Passing the PR worktree path into the pasted poll block:** not applied. It would add a second
  value to fill in when pasting. Instead the script's detached-HEAD message names the cause.
