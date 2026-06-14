-- 103_github_events_retention_7day.down.sql
-- Reversal of 103_github_events_retention_7day.sql — restore the 094 90-day
-- schedule on processed_github_events_retention.
--
-- !!! WARNING — DO NOT APPLY THIS DOWN TO PROD AS AN INCIDENT ROLLBACK. !!!
-- Restoring the 90-day window re-arms the exact pathology this migration fixes:
-- the table re-bloats toward ~450k rows, the Disk-IO budget re-depletes, and
-- the monitor re-files issue #5225. This down exists ONLY for migration-
-- framework reversibility (e.g., to reconstruct prior schema in a fresh env);
-- it is never the right operational response to a problem.
--
-- The rows purged by the up migration's one-time DELETE are NOT restored
-- (a retention sweep is lossy by design — mirrors 094.down).

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_github_events_retention') THEN
    PERFORM cron.unschedule('processed_github_events_retention');
  END IF;
  PERFORM cron.schedule(
    'processed_github_events_retention',
    '0 4 * * *',
    $$DELETE FROM public.processed_github_events WHERE received_at < now() - interval '90 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;
