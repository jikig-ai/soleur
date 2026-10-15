---
feature: feat-one-shot-9307-generic-affected-gate
date: 2026-10-15
---

# Decision Challenges — PR 2 of #9307 (plugin-generic affected test gate)

This run had no Task/agent spawn path (Devin subagent), so technical rulings that would
have gone to `soleur:engineering:cto` are recorded as `pending - assumed:` per
technical-ruling-delegation.md §6; each names the default the plan assumes.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| D1 single gate entry point (`affected-tests.sh`) replacing the `test-all.sh --affected` call sites vs an additive no-runner fallback arm at each site | technical | Ruled by prior process, 2026-09-30 (umbrella plan review): single dispatcher entry point - the capability probe owns runner-vs-adapter choice so skills carry no branching; carried forward |
| D2 `budget_seconds` default 900 (unmeasured) | technical | pending - assumed: 900 s per the reviewed umbrella plan; labelled unmeasured in the plan and overridable via `.soleur-test-gate.json` |
| D3 capability probe targets the `--print-selection` registration token (newest #9307-interface marker) rather than `--print-affected-set` | technical | pending - assumed: `--print-selection`; Guard 2 fixtures assert comment-only text does not count, so a wrong token choice fails loudly rather than silently delegating |
| D4 deliverable 3 (#8231 parallel scheduler) is a documented non-goal for this PR | technical | precondition evaluated 2026-10-15 and fails: #7376 open, #7454 deferral stands, 2026-10-09 #8231 comment records the dominant local cost is now the pre-pass and parallelism stays behind its green-baseline precondition - recorded per the run brief, no ruling needed |
| D5 `TEST_GROUP=affected` seat-scoping line in review/work left in place; the gate is wired at lead-gate positions only | technical | pending - assumed: leave it; #10333 owns the convergence/coverage-computation ask and rewiring seat scope here would absorb a parked sibling issue |
