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

-- 4. Restore the simpler set_conversation_visibility from migration 075.
-- The 076 up migration overrode it with workspace_activity INSERT logic;
-- now that workspace_activity is gone, restore the non-event-emitting version.
CREATE OR REPLACE FUNCTION public.set_conversation_visibility(
  p_conversation_id uuid,
  p_visibility text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_visibility NOT IN ('private', 'workspace') THEN
    RAISE EXCEPTION 'Invalid visibility value: %', p_visibility
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.conversations
     SET visibility = p_visibility
   WHERE id = p_conversation_id
     AND user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation not found or not owned by caller'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_conversation_visibility(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_conversation_visibility(uuid, text)
  TO authenticated;
