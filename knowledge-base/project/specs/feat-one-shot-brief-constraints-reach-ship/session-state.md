# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-06-feat-propagate-brief-constraints-to-ship-plan.md
- Status: complete
- cto_spawns=3 (planner-side)

### Errors
None (planner: hook refused a tracker issue until meta/machinery label added; MD038 lint fixed).

### Decisions
- D7 inherited: one-shot writes `## Operator Constraints` with `- ci-is-the-gate: <words>` token into this file; battery-owed.sh reads it and exits 42 before conditions 1, 2, 4.
- Own NUL-delimited rename-free path list so untracked/C-quoted infra paths still count.
- Net bytes: ship -146, one-shot -3; skill-body-budget.json untouched.
- Work/review not covered: tracker 12247. Non-token infra C-quote gap: tracker 12251.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, CTO x3, review panel x3, deepen agents x3
