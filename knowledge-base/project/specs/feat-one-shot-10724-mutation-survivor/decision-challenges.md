# Decision Challenges — feat-one-shot-10724-mutation-survivor

Pipeline decision log for the plan at `knowledge-base/project/plans/2026-10-22-test-scan-hidden-join-mutant-survivor-plan.md` (issue #10724). Headless one-shot context: no `AskUserQuestion` gates fire; technical forks are CTO-seat rulings per `technical-ruling-delegation.md`.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Fix design fork — deterministic op/line-event-class instrument (test-side materialization probe on `index.paths`/`index.tracked`) vs. relaxed CPU bound vs. row-window restructure | technical | pending - assumed: **deterministic test-side materialization probe** (kills the join-and-find class without any clock dependence; zero SUT diff so no collision with PR #10851; ~15 lines inside `row_scan_ops`). Relaxed-CPU rejected (weakens every row, stays probabilistic); window-restructure kept as documented fallback. No Agent/Task/run_subagent tool is available in this planning subagent context, so the `soleur:engineering:cto` spawn could not run — the review seat or a follow-up CTO spawn should confirm or overturn before ship. |
| Two sibling evasion mutants added beyond the literal ask (`scan-hidden-sorted-tracked-per-scan`, `scan-hidden-tuple-paths-per-scan`) | technical | pending - assumed: **add** — the bypass-model learning (a battery tested only against the observed spelling re-opens the class); each mutant exercises a different probe for ~2 lines + floor bumps. Same caveat: no CTO spawn available. |
