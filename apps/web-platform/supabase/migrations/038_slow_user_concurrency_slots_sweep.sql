-- 038_slow_user_concurrency_slots_sweep.sql
--
-- Reduce the pg_cron sweep on public.user_concurrency_slots from once-per-
-- minute to once-per-15-minutes. The 120-second `last_heartbeat_at`
-- freshness threshold (declared in 029) is independent of sweep cadence;
-- this migration only changes how often dead rows are physically reaped.
--
-- At current scale (38 deletes across 14+ days, 0 live slots in steady
-- state) the per-minute cadence was producing ~5,760 cron-internal writes
-- per day to cron.job_run_details for ~3 useful deletes per day. Slowing
-- to 15 minutes drops cron-internal writes to ~384/day with no functional
-- impact on stuck-active recovery (handled separately by migration 037's
-- find_stuck_active_conversations RPC + agent-runner.ts:522 setInterval).
--
-- See: knowledge-base/project/plans/2026-05-06-fix-supabase-disk-io-cron-realtime-plan.md
-- See: knowledge-base/project/learnings/2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale.md
-- Issue: #3358

DO $$
BEGIN
  -- Idempotent guard: only act if the named job exists.
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep') THEN
    PERFORM cron.unschedule('user_concurrency_slots_sweep');
  END IF;

  PERFORM cron.schedule(
    'user_concurrency_slots_sweep',
    '*/15 * * * *',
    $sweep$
      delete from public.user_concurrency_slots
      where last_heartbeat_at < now() - interval '120 seconds';
    $sweep$
  );
END $$;
