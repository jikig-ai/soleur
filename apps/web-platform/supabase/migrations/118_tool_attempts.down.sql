-- 118_tool_attempts.down.sql — revert 118_tool_attempts.sql.
-- Unschedule the retention cron first (guarded), then drop the table.

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tool_attempts_retention') THEN
    PERFORM cron.unschedule('tool_attempts_retention');
  END IF;
END $cron_block$;

DROP TABLE IF EXISTS public.tool_attempts;
