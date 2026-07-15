# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-14-fix-inngest-watchdog-functions-query-corroboration-and-restart-lock-contention-plan.md
- Status: complete (first subagent crashed on transient API error → re-spawned; retry succeeded; committed 833108d28 plan, c55667b2d deepen)

### Decisions
- Root cause re-scoped away from stale redis hypothesis: inngest was UP (SQLite+Postgres, no redis) and processing events during the "outage".
- Defect A: watchdog `/v0/gql` functions query transient `__FETCH_FAILED__` → classifier declared `inngest_down` before any liveness check. Fix: loopback `/health` corroboration (NOT systemctl is-active, which masks a wedged server) + new soft mode `functions_query_degraded`.
- Defect B: dispatched restart RED-failed on `flock` lock_contention. Fix: apply existing ADR-079 amendment #5960 "lock_contention is non-terminal" + final STATE re-read to the restart verify poll (consumer-only, preserves ADR-100 restart purity).
- Union-widening: soft mode hits 4 watchdog consumers (2 default dangerously to `down`) — all mandatory-edited + auto-close branch + `failure_mode ==` sweep AC.
- (C) SOLEUR_* observability markers for both decisions; host-config via immutable redeploy not SSH.

### Components Invoked
- soleur:plan, soleur:deepen-plan; research: learnings-researcher, Explore×; deepen review: architecture-strategist, code-simplicity-reviewer, pattern-recognition-specialist.
