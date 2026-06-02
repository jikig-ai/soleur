-- 094_dedup_tables_retention.down.sql
-- Reversal of 094_dedup_tables_retention.sql — unschedule both retention crons.
-- The dedup rows themselves are not restored (a retention sweep is lossy by
-- design); reverting only stops the future pruning.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_github_events_retention') THEN
    PERFORM cron.unschedule('processed_github_events_retention');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_stripe_events_retention') THEN
    PERFORM cron.unschedule('processed_stripe_events_retention');
  END IF;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;
