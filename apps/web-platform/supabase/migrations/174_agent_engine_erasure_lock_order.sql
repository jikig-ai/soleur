BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';

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
  -- Match owner rebind ordering: workspace, run, then recovery checkpoint.
  PERFORM w.id FROM public.workspaces AS w
   WHERE EXISTS (SELECT 1 FROM public.agent_engine_runs AS r
                  WHERE r.workspace_id = w.id AND r.created_by = p_user_id)
      OR EXISTS (SELECT 1 FROM public.workspace_engine_settings AS s
                  WHERE s.workspace_id = w.id AND s.updated_by = p_user_id)
   ORDER BY w.id FOR UPDATE OF w;
  PERFORM r.id FROM public.agent_engine_runs AS r
   WHERE r.created_by = p_user_id ORDER BY r.id FOR UPDATE OF r;
  DELETE FROM public.agent_engine_recovery_checkpoints AS c
   USING public.agent_engine_runs AS r
   WHERE c.run_id = r.id AND r.created_by = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_count := v_rows;
  UPDATE public.workspace_engine_settings
    SET updated_by = NULL WHERE updated_by = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_count := v_count + v_rows;
  UPDATE public.agent_engine_runs
    SET created_by = NULL WHERE created_by = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_count + v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_agent_engine_recovery_checkpoint(
  p_run_id uuid, p_attempt_id uuid, p_checkpoint jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_run_generation bigint;
  v_created_by uuid;
  v_attempt_generation bigint;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine recovery requires service role' USING ERRCODE = '42501';
  END IF;
  IF p_checkpoint IS NULL OR jsonb_typeof(p_checkpoint) IS DISTINCT FROM 'object'
     OR octet_length(p_checkpoint::text) > 16384 THEN
    RAISE EXCEPTION 'invalid recovery checkpoint' USING ERRCODE = '22023';
  END IF;
  SELECT r.auth_mode_generation, r.created_by INTO v_run_generation, v_created_by
    FROM public.agent_engine_runs AS r WHERE r.id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine run not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_created_by IS NULL THEN
    RAISE EXCEPTION 'engine run was anonymised' USING ERRCODE = '55000';
  END IF;
  SELECT a.auth_mode_generation INTO v_attempt_generation
    FROM public.agent_engine_attempts AS a
   WHERE a.id = p_attempt_id AND a.run_id = p_run_id;
  IF NOT FOUND OR v_attempt_generation IS DISTINCT FROM v_run_generation THEN
    RAISE EXCEPTION 'engine attempt auth mode is stale' USING ERRCODE = '55000';
  END IF;
  INSERT INTO public.agent_engine_recovery_checkpoints(run_id, checkpoint)
  VALUES (p_run_id, p_checkpoint)
  ON CONFLICT (run_id) DO UPDATE SET checkpoint = EXCLUDED.checkpoint, updated_at = now();
END;
$$;

COMMIT;
