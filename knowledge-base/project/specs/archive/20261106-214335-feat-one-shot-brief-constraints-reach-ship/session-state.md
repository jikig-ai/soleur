# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-06-feat-propagate-brief-constraints-to-ship-plan.md
- Status: complete
- cto_spawns=3 (planner-side)

### Errors

None (planner: hook refused a tracker issue until meta/machinery label added; MD038 lint fixed).

### Decisions

- D7 inherited: one-shot writes `## Operator Constraints` with a `- ci-is-the-gate: <words>` token into this file; battery-owed.sh reads it and exits 42 before conditions 1, 2 and 4.
- Own NUL-delimited rename-free path list so untracked and C-quoted infra paths still count.
- Net bytes: ship -146, one-shot -3; skill-body-budget.json untouched.
- Work and review are not covered: tracker 12247. Non-token infra C-quote gap: tracker 12251.

### Components Invoked

soleur:plan, soleur:plan-review, soleur:deepen-plan, CTO x3, review panel x3, deepen agents x3

## Operator Constraints

- constraint: Rely on CI's required test check. Required checks: test, lockfile-sync, markdown-lint, tenant-integration-required. Read infra-validation and sandbox-canary-capture-gate by hand. Do not run the local affected battery to completion.
- constraint: Never push to a PR that is in the merge queue. Never --admin merge. Never touch the ruleset.
- ci-is-the-gate: Rely on CI required test check, do not run the local affected battery to completion.
