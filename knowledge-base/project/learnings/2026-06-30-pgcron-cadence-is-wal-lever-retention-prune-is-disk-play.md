# Learning: pg_cron cadence is the WAL lever; a retention prune is only a disk/cache play

## Problem

Issue #5738 asked to cut the ~4.7%-of-WAL contribution of `cron.job_run_details`
on a prod Micro Supabase instance. The issue's option list led with "add a daily
retention prune" — which feels like the obvious fix for an unbounded log table.
But a retention DELETE does **not** reduce the WAL that the issue is about: the
WAL comes from the per-run `INSERT INTO cron.job_run_details`, and the prune's own
`DELETE` is itself WAL-logged. Pruning bounds table SIZE (disk/cache pressure), it
does not reduce INSERT WAL.

A second trap: the obvious WAL lever (throttle the noisy job's cadence) interacts
with code that *depends on that job for reaping*. `user_concurrency_slots_sweep`
ran `*/15`; throttling it to hourly widens the window in which crashed-but-unreaped
rows linger. One consumer — the cap-drift session-evict count in `ws-handler.ts` —
counted slots with **no** freshness filter, so the slower sweep would have widened
a false-eviction window ~4x (a latent bug, not introduced by the throttle but
amplified by it).

## Solution

- **Identify the real WAL lever before picking a fix.** WAL is dominated by writes
  (INSERTs + their full-page images). For a per-run log table, the lever is *fewer
  runs* (cadence), not *fewer rows* (retention). Throttling `user_concurrency_slots_sweep`
  `*/15 → hourly` cut ~96→24 runs/day (~56% fewer INSERTs); the retention prune was
  kept too, but framed honestly as a disk/cache play, not a WAL play.
- **When throttling a sweep other code relies on, freshness-filter every consumer.**
  Grep all readers of the swept table (`user_concurrency_slots`) and confirm each
  applies the liveness predicate (`.gte`/`.lt last_heartbeat_at`, or an inline
  self-reap). The acquire RPC self-reaped inline; two sibling probes filtered; the
  cap-drift count did not — fixed in the same PR with `.gte("last_heartbeat_at", liveCutoff)`.
- **`COALESCE(end_time, start_time)` for retention on a table with in-flight NULLs.**
  A bare `end_time < …` never reaps crash-orphaned NULL-`end_time` rows; COALESCE
  reaps by start_time while leaving genuinely in-flight and both-NULL rows.
- **Do NOT index the log table to make the prune sargable.** An index on
  `start_time`/`end_time` adds WAL on every INSERT — directly counter to the goal.
  A daily seq-scan delete at tens-of-thousands of rows is sub-second; keep it
  index-free and run it decoupled from the migration transaction.
- **Verify on dev via Supabase MCP, not the dashboard** (`hr-no-dashboard-eyeball-pull-data-yourself`):
  idempotent re-apply (one job each), prune-predicate fixtures (both-NULL +
  in-flight retained, 7-day boundary), and a live drain (27,891→896 rows).

## Key Insight

For write-dominated WAL, the lever is the write *rate*, not the table *size*. A
retention prune and a cadence throttle look interchangeable but aren't: the throttle
reduces WAL, the prune reduces disk. And throttling a sweep is only safe once every
consumer that reads the swept table tolerates the longer staleness window — verify
that before changing the cadence, not after.

## Session Errors

None encountered in the work/review/QA phases. (Forwarded from planning: a Write was
correctly blocked from the bare-root checkout and redirected to the worktree path; an
Edit retried after a benign linter touch — both resolved. The bare-root block is a
working guard, not a defect. **Prevention:** already enforced by the bare-repo-CWD
guard + worktree-absolute paths.)

## Tags
category: performance-issues
module: supabase-pg-cron
issue: 5738
related: 5739, 5736
