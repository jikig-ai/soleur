-- 076_workspace_activity.down.sql
-- Reversal of 076_workspace_activity.sql

-- 1. Unschedule pg_cron job
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'workspace_activity_purge') THEN
    PERFORM cron.unschedule('workspace_activity_purge');
  END IF;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- 2. Drop functions
DROP FUNCTION IF EXISTS public.anonymise_workspace_activity(uuid);
DROP FUNCTION IF EXISTS public.record_workspace_activity(uuid, uuid, text, jsonb);

-- 3. Drop table (CASCADE drops policies + indexes)
DROP TABLE IF EXISTS public.workspace_activity CASCADE;
