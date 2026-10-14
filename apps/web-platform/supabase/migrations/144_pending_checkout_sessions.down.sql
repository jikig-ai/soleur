-- Down for 144_pending_checkout_sessions.sql.
-- Dropping the table forfeits in-flight dedup protection — the #8918
-- double-session window reopens; only run paired with a code revert.
-- The retention cron job is unscheduled first so it doesn't error nightly
-- against a missing table.
DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pending_checkout_sessions_retention') THEN
    PERFORM cron.unschedule('pending_checkout_sessions_retention');
  END IF;
END $cron_block$;

DROP TABLE IF EXISTS public.pending_checkout_sessions;
