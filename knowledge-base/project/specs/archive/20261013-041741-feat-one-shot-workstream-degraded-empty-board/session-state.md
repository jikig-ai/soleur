# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-15-fix-workstream-degraded-empty-board-false-empty-state-plan.md
- Status: complete

### Errors
None. CWD verified; branch safe; premise validated (bug pre-existing, predates PR #6308). Deepen-plan gates 4.6/4.7/4.8 passed.

### Decisions
- Option A: throw typed `WorkstreamDegradedError` → route 502 → SWR retains prior data + existing `refreshFailed` banner. Reject Option B (fights SWR, widens type).
- Broader root cause: line 99 `getCurrentRepoUrl` fails-open to null on transient errors is ALSO a degraded path (P2), not just line 107 (P1). Fix both via additive `readCurrentRepoUrlResult(): {url, degraded}`; keep `getCurrentRepoUrl` thin wrapper (≈11 call sites untouched).
- Mirror-then-throw: keep Sentry mirroring at each degrade source; add workstream-scoped `op:"repo-unresolved"` mirror at P2 throw.
- Fold in user-impact FINDING 2 (disable "+ New Issue" during first-load degrade); defer FINDING 1 (permanent-revoke reconnect affordance) with tracking issue.
- Threshold = single-user incident; requires_cpo_signoff; user-impact-reviewer at review time.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Agents: code-simplicity-reviewer, architecture-strategist, observability-coverage-reviewer, user-impact-reviewer, learnings-researcher
- Deliverables: plan .md + tasks.md committed (5a08696bf)
