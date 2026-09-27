# Decision challenges — feat-one-shot-8211-pr2-pm4-docs

Taste decisions from the plan review, recorded under the headless arm and not auto-applied
(ADR-084). The operator's stated direction is the default.

## DC-1: tick a separate `#7226` item under the Preconditions bullet (Taste, kept)

- **Operator direction:** "tick the issue-7226 item under Preconditions".
- **Challenge (DHH):** the item that host-key step 4 names is the `[x] Step 4` sub-item, which PR
  #9036 already ticked. A new `#7226` checkbox records the same fact a second time.
- **Kept because:** the brief asks for it explicitly, and the parent bullet `**#7226 / #5914**` has
  no checkbox that shows #7226 is closed. The v2 wording no longer claims anything about steps 1–3.
- **Reopen if:** the operator prefers no new checkbox. Delete the one added line.

## DC-2: restate the ADR-237 clause on the same C4 edge (Taste, kept)

- **Challenge (code-simplicity):** the clause belongs to another decision (ADR-237), and PR #9036
  left it alone. It is outside the requested scope.
- **Kept because (DHH concurred):** the edge's new "root authentication LIVE" claim depends on the
  pinned hops. Leaving "effective when the strict dry run … reads ok" in the same label would show
  the pins as pending beside a LIVE claim that rests on them.
- **Reopen if:** the operator wants the PR limited strictly to the D1b marker. Revert Phase 5 step 3.

## DC-3: the Post-merge order step 5 record names two runs (Mechanical correction to the brief)

- **Operator direction:** mark step 5 done "citing run 36339208990".
- **Measured:** run 35119099336 (2026-09-16) first met step 5 as it was worded then, and closed #8189
  and #6680. Run 36339208990 meets the current wording, which includes the fence probe.
- **Resolution:** the Done line cites both runs. Citing only the 2026-09-27 run would misdate when
  the step was first met.
