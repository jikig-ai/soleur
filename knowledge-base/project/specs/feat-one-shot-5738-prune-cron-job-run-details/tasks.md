---
title: "Tasks: prune + throttle pg_cron cron.job_run_details"
issue: 5738
lane: single-domain
plan: knowledge-base/project/plans/2026-06-30-perf-prune-throttle-cron-job-run-details-plan.md
---

# Tasks — perf(db): prune + throttle `cron.job_run_details`

## Phase 0 — Preconditions + paired safety fix (/work)

- [x] 0.1 Live-probe (dev, Supabase MCP `execute_sql`): confirm
  `DELETE FROM cron.job_run_details WHERE COALESCE(end_time,start_time) < now() - interval '7 days'`
  runs without a permission error; also `SELECT count(*) FROM cron.job_run_details`
  to quantify the backlog (seq-scan drain; if very large, note for an optional
  batched one-off outside the migration).
- [x] 0.2 Confirm latest migration prefix is still `113` (else renumber to next free).
- [x] 0.3 Re-read migration `038`'s slots-DELETE body to copy it functionally.
- [x] 0.4 Precedent-diff: open `103_github_events_retention_7day.sql` as the shape template.
- [x] 0.5 **Safety fix:** in `apps/web-platform/server/ws-handler.ts:768-772`, add
  `.gte("last_heartbeat_at", liveCutoff)` (120 s cutoff) to the cap-drift evict
  count, mirroring the sibling probe at `:2004-2015`. Run `tsc --noEmit`.

## Phase 1 — Forward migration (two statements, no one-time purge)

- [x] 1.1 Create `apps/web-platform/supabase/migrations/114_prune_cron_job_run_details.sql`.
- [x] 1.2 Statement A: idempotent reschedule of `user_concurrency_slots_sweep` to
  `0 * * * *` (DELETE body + `120 seconds` interval functionally unchanged from 038).
- [x] 1.3 Statement B: idempotent `cron.schedule('cron_job_run_details_retention',
  '0 4 * * *', $$DELETE FROM cron.job_run_details WHERE COALESCE(end_time,start_time) < now() - interval '7 days'$$)`.
- [x] 1.4 Header comment: cite #5738, the investigation learning, 96→24 delta, R1
  safety rationale (incl. the Phase 0 ws-handler fix), 103 precedent, COALESCE
  rationale, and that the daily job drains the backlog in isolation.

## Phase 2 — Down migration

- [x] 2.1 Create `114_prune_cron_job_run_details.down.sql`: reschedule slots sweep
  back to `*/15 * * * *`; `cron.unschedule('cron_job_run_details_retention')` (guarded).
  (Phase 0 ws-handler fix is a strict improvement — not reverted.)

## Phase 3 — Verify

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green (Phase 0 edits ws-handler.ts).
- [x] 3.2 Apply on dev; assert idempotency (apply twice → one row each).
- [x] 3.3 `SELECT jobname, schedule FROM cron.job ORDER BY jobname` → slots sweep
  `0 * * * *`, retention job present.
- [x] 3.4 Prune correctness on dev: old rows gone; in-flight (NULL end_time, recent
  start_time) and both-NULL (`status='starting'`) rows retained.
- [x] 3.5 Cap-drift fix: live session + synthetic stale slot for same user → a
  downgrade refresh does NOT evict the live session.

## Phase 4 — Ship

- [ ] 4.1 PR body uses `Ref #5738` (NOT `Closes` — verification is post-merge).
- [ ] 4.2 Post-merge: re-measure run-rate (~128→~56/day) via MCP; then `gh issue close 5738`.
