---
feature: feat-one-shot-9307-generic-affected-gate
date: 2026-10-15
---

# Decision Challenges — PR 2 of #9307 (plugin-generic affected test gate)

Technical rulings were issued by a single batched `soleur:engineering:cto` consult
(2026-10-15) per technical-ruling-delegation.md; each row's Ruling cell carries the ruling.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| D1 single gate entry point (`affected-tests.sh`) replacing the `test-all.sh --affected` call sites vs an additive no-runner fallback arm at each site | technical | Ruled by CTO agent, 2026-10-15: ratified - single `affected-tests.sh` dispatcher; all five call sites prescribe `scripts/test-all.sh --affected` with no no-runner arm, and an additive `[[ -f ]]` fallback would duplicate a filename-based decision the capability probe exists to avoid while creating two entry points that drift |
| D2 `budget_seconds` default 900 (unmeasured) | technical | Ruled by CTO agent, 2026-10-15: ratified at 900 - the budget fires only when a real CI test workflow is detected (no CI = ignored with an upfront line), so the cap can never ship an unverified change; 15 min sits above measured affected runs (~150 s contended pre-pass) and below the >30 min serial-gate pain that opened #9307; `.soleur-test-gate.json`/`budget_ci` cover the tails |
| D3 capability probe targets the `--print-selection` registration token (newest #9307-interface marker) rather than `--print-affected-set` | technical | Ruled by CTO agent, 2026-10-15: ratified - `--print-selection` is the diff-aware interface marker; `--print-affected-set` prints registration classes and ignores the diff, so probing it would delegate to a runner lacking the selection capability; Guard 2 row 4's comment-only fixture pins the probe to the registration token rather than free text |
| D4 deliverable 3 (#8231 parallel scheduler) is a documented non-goal for this PR | technical | Ruled by CTO agent, 2026-10-15: ratified as non-goal - the 2026-10-09 measurement record shows #7376's interference signature unresolved, #7454's deferral standing, and intra-run parallelism would not touch the dominant cost now that the pre-pass dominates; absorbing #8231 here adds risk with no measured payoff |
| D5 `TEST_GROUP=affected` seat-scoping line in review/work left in place; the gate is wired at lead-gate positions only | technical | Ruled by CTO agent, 2026-10-15: ratified - `TEST_GROUP=affected` is per-seat scoping for spawned agents, a different mechanism from the lead gate; #10333 owns the convergence/coverage-computation ask and rewiring it here would absorb a parked sibling issue. Conditional on the plan's compensating clause routing no-runner spawned seats to the plugin gate (plan §risk table records the #10333 merge-order fork) |
