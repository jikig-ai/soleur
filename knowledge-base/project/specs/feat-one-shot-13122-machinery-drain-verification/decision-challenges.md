# Decision Challenges — feat-one-shot-13122-machinery-drain-verification

Planning-time technical rulings (2026-11-28). The authoring harness exposed no independent CTO spawn path, so the challenge was performed inline against the issue text, live API evidence, and probe precedents. No User-Challenge rows: none of the rulings drops requested scope.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Enroll the directive on #13122 itself and let the implementation PR close it | taste | Ruled inline, 2026-11-28: use a separate post-merge tracker; the implementation PR uses `Ref #13122`, and enrollment happens after merge — a tracker closed at merge is no longer a visible open verification obligation; this matches the #10585 precedent. |
| Treat the literal first completed row, even `cancelled`/`skipped`, as the permanent measurement target | taste | Ruled inline, 2026-11-28: skip cancelled/skipped rows as non-measurements, but do not skip a non-cancelled run with missing Drain evidence — literalism would wedge verification forever behind a row that never exercised the actor gate, while silently skipping all missing evidence could hide a broken run. |
| Use an earliest at filing time/merge time and let the script emit daily NOT YET comments before Monday | taste | Ruled inline, 2026-11-28: use `earliest=2026-11-30T18:00:00Z`, the first sweep after the first expected weekly dispatch — the earlier arm is safer against surprise timing but creates low-value tracker comments; the script's own exit-2 gate remains the true availability test. |
| Treat any `closed=0` successful drain as proof because the actor gate is independent of drain efficacy | taste | Ruled inline, 2026-11-28: PASS only for `closed>0`, explicit `WAIVED-*`, or substantive non-actor `##[error]` diagnosis; otherwise CANNOT ESTABLISH — a vacuous `closed=0` cannot distinguish ineffective drain logic from actor-adjacent action failure, so refusing a cheap PASS preserves the issue's evidence bar. |
