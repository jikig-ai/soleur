---
status: budget-capped
stopped_at: review-phase design-pass boundary
dimension: seats
count: 13
cap: 12
---

## Budget-capped stop

`pipeline-tally.sh gate seats` → STOP (seats=13 ≥ cap=12; WARN recorded at 11).
Panel seats spawned so far: 2 (design pass). Remaining panel: 7 seats pending.

Resume options:
- `pipeline-tally.sh init --max-seats <N>` (raised cap) then re-run `soleur:review` — the panel continues under the new budget.
- `pipeline-tally.sh init --reset` clears the latch AND the counts (loses the tally).

## Resume record (2026-10-03)

Operator chose raised cap: `init --max-seats 20`. The ledger had been untouched
>24h, so init took the `stale-reset` outcome and ZEROED all counts — the latch
cleared and cap=20 took effect, but the running tally was lost.

Pre-reset tally (for the final report — restore or cite, do not re-fabricate):
seats=13 ci_cycles=4 fix_rounds=1 agent_rounds=7; warned:seats=11 capped:seats=12.

Dogfood note: a >24h pause on a capped stop always loses the tally on resume —
the final report cannot show the true total unless pre-reset counts are carried.
Consider whether the ship-render spec should read a preserved snapshot.

**Resolved in the review fix round:** `capped-reset` now beats `stale-reset`
when raised `--max-*` argv is supplied — the raised cap is unambiguous resume
intent, so a >24h paused capped run keeps its counts. `stale-reset` still fires
for a bare init on a stale ledger (no argv intent → foreign-run protection),
and `gate` refreshes ledger mtime on every read so a quiet-but-live pipeline
no longer zeroes itself. The preserved snapshot above still applies to THIS
run (the loss predated the fix); cite it in the PR body's tally section.
