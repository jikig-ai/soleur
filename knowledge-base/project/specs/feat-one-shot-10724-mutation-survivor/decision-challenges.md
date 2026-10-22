# Decision Challenges — feat-one-shot-10724-mutation-survivor

Pipeline decision log for the plan at `knowledge-base/project/plans/2026-10-22-test-scan-hidden-join-mutant-survivor-plan.md` (issue #10724). Headless one-shot context: no `AskUserQuestion` gates fire; technical forks are CTO-seat rulings per `technical-ruling-delegation.md`.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Fix design fork — deterministic op/line-event-class instrument (test-side materialization probe on `index.paths`/`index.tracked`) vs. relaxed CPU bound vs. row-window restructure | technical | Ruled by CTO agent, 2026-10-22: adopt the test-side materialization probe, AMENDED on verified seat dissent — `_SetProbe` is a plain-object delegating wrapper (`_d`+`hits`, `__len__`, uncounted `__contains__`, counting `__iter__`), NOT a set subclass (a subclass leaks `copy()`/`set()`/`frozenset()`/`|`/union-family at hits=0 — a one-edit silent escape of the very class); `_SeqProbe.__getitem__` counts every access (closes `reversed()`/int-index genexpr). Accepted residuals shrink to `._d`/`__dict__` raw access and `copy.copy()` (insider/two-edit spellings only). |
| Two sibling evasion mutants added beyond the literal ask (`scan-hidden-sorted-tracked-per-scan`, `scan-hidden-tuple-paths-per-scan`, `scan-hidden-copy-tracked-per-scan`) | technical | Ruled by CTO agent, 2026-10-22: add all three and the same-edit floor re-measure — sorted/tuple exercise both probes, and `index.tracked.copy()` crash-kills on the amended wrapper (AttributeError → whitelisted in `CRASH_IS_THE_POINT`), pinning the no-delegation contract; `FLOOR_MUTANTS` 298→301, `FLOOR_ASSERTIONS` re-measured. |
