# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-30-perf-prune-throttle-cron-job-run-details-plan.md
- Status: complete

### Errors
None. (One Write was correctly blocked from the bare-root checkout and redirected to the worktree path; one Edit retried after a benign linter touch — both resolved.)

### Decisions
- Combine throttle (option 2) + retention prune (option 1); throttle is the load-bearing WAL lever. `user_concurrency_slots_sweep` `*/15`→hourly cuts total cron runs ~128→~56/day. Both in migration 115.
- Throttle verified user-safe: acquire RPC (093:79-81) self-reaps caller's stale slots inline. Folded in a one-line `.gte("last_heartbeat_at", liveCutoff)` fix at ws-handler.ts:768-772 (Phase 0) removing a latent over-eviction bug.
- Dropped the one-time purge (unindexed table, non-sargable COALESCE → seq-scan delete under --single-transaction risked rolling back the throttle). Daily `0 4 * * *` job drains backlog in isolation; 7-day retention floor preserved.
- Rejected option 3 (disable run logging — needs superuser/Management API, conflicts with observability AC). No ADR/C4 change.
- Used COALESCE(end_time, start_time) to reap crash-orphaned NULL-end_time rows. PR #5736 merge confirmed.

### Components Invoked
- Skill soleur:plan (#5738), soleur:deepen-plan (gates 4.6/4.7/4.8/4.9 pass; precedent-diff 4.4 satisfied)
- Agents: data-integrity-guardian, code-simplicity-reviewer (parallel)
- gh, git, repo grep/read for premise validation
