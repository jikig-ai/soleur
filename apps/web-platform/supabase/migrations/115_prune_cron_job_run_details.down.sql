-- 114_prune_cron_job_run_details.down.sql
--
-- Reverse 114: restore the immediately-prior pg_cron state.
--   1. Reschedule user_concurrency_slots_sweep back to */15 * * * * (its state from
--      migration 038), body unchanged.
--   2. Unschedule cron_job_run_details_retention (guarded by IF EXISTS).
--
-- Not reverted: the ws-handler.ts:768 cap-drift freshness filter shipped in the same
-- PR (#5738) is a strict correctness improvement (removes a latent false-eviction
-- bug) and is independent of the cron cadence — leave it in place.
--
-- Not restorable: rows already deleted by the retention prune are irrecoverable
-- (observability-only cron logs; acceptable loss on a down-migration).
--
-- Idempotent + atomic, same shape/guards as the up migration.
-- See: 114_prune_cron_job_run_details.sql · Issue: #5738

-- =====================================================================
-- 1. Restore the slots sweep to */15 (was hourly under 114)
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep') THEN
    PERFORM cron.unschedule('user_concurrency_slots_sweep');
  END IF;
  PERFORM cron.schedule(
    'user_concurrency_slots_sweep',
    '*/15 * * * *',  -- restore mig 038 cadence
    $sweep$delete from public.user_concurrency_slots where last_heartbeat_at < now() - interval '120 seconds';$sweep$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;

-- =====================================================================
-- 2. Remove the retention prune job
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cron_job_run_details_retention') THEN
    PERFORM cron.unschedule('cron_job_run_details_retention');
  END IF;
END $cron_block$;
