# Decision Challenges — feat-one-shot-10724-mutation-survivor

Pipeline decision log for the plan at `knowledge-base/project/plans/2026-10-22-test-scan-hidden-join-mutant-survivor-plan.md` (issue #10724). Headless one-shot context: no `AskUserQuestion` gates fire; technical forks are CTO-seat rulings per `technical-ruling-delegation.md`.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Fix design fork — deterministic op/line-event-class instrument (test-side materialization probe on `index.paths`/`index.tracked`) vs. relaxed CPU bound vs. row-window restructure | technical | Ruled by CTO agent, 2026-10-22: adopt the test-side materialization probe - verified sound: join/tuple/sorted/slice on a non-list `_SeqProbe` dispatch to counted `__iter__`/`__getitem__`, `set.__contains__` bypasses `__iter__` so O(1) membership stays legal, the pristine scan path never touches `index.paths`/`index.tracked` so the counter holds 0; the kill lands before the CPU phase, zero SUT diff, no clock. Relaxed-CPU rejected (weakens every row, stays probabilistic); window-restructure kept as documented fallback. Residuals named in the plan's bypass model: `index.paths._d`/`__dict__` raw-list access and `copy.copy(index.paths)` silently escape (insider-knowledge / two-edit spellings only); `.copy()` crashes loudly. |
| Two sibling evasion mutants added beyond the literal ask (`scan-hidden-sorted-tracked-per-scan`, `scan-hidden-tuple-paths-per-scan`) | technical | Ruled by CTO agent, 2026-10-22: add both siblings and the same-edit floor re-measure - a battery tested only against the observed spelling re-opens the class; `scan-hidden-sorted-tracked-per-scan` is the sole exercise of `_SetProbe` (otherwise unverified decoration), `tuple(index.paths)` covers the tuple/list spelling; ~2 lines plus mandatory `FLOOR_MUTANTS` 298→300 and `FLOOR_ASSERTIONS` re-measure per the file's same-edit convention. |
