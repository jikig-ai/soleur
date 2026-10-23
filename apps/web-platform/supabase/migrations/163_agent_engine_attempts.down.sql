BEGIN;
DROP FUNCTION IF EXISTS public.get_agent_engine_recovery_checkpoint(uuid);
DROP FUNCTION IF EXISTS public.save_agent_engine_recovery_checkpoint(uuid, jsonb);
DROP FUNCTION IF EXISTS public.append_agent_engine_lifecycle_event(uuid, uuid, jsonb);
DROP FUNCTION IF EXISTS public.transition_agent_engine_attempt(uuid, text);
DROP FUNCTION IF EXISTS public.start_agent_engine_attempt(uuid, text);
DROP TABLE IF EXISTS public.agent_engine_recovery_checkpoints;
ALTER TABLE public.agent_engine_events DROP COLUMN IF EXISTS attempt_id;
DROP TABLE IF EXISTS public.agent_engine_attempts;

CREATE OR REPLACE FUNCTION public.anonymise_agent_engine_data(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_count integer := 0;
        v_rows integer;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'agent engine anonymisation requires service role' USING ERRCODE = '42501';
  END IF;
  UPDATE public.workspace_engine_settings
    SET updated_by = NULL WHERE updated_by = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_count := v_rows;
  UPDATE public.agent_engine_runs
    SET created_by = NULL WHERE created_by = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_count + v_rows;
END;
$$;
COMMIT;
