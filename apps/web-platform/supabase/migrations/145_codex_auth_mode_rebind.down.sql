BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';

-- Bound Codex runs retain their auth_mode when this preference column is removed.
-- If migration 145 is reapplied, those run bindings backfill the last Codex mode;
-- a workspace with no Codex conversations returns to the managed default.
DROP FUNCTION IF EXISTS public.set_workspace_default_engine(uuid, text, text, boolean, integer);
DROP FUNCTION IF EXISTS public.count_codex_conversation_rebinds(uuid, text);
DROP FUNCTION IF EXISTS public.assert_agent_engine_attempt_generation(uuid);
DROP FUNCTION IF EXISTS public.save_agent_engine_recovery_checkpoint(uuid, uuid, jsonb);
DROP INDEX IF EXISTS public.agent_engine_runs_codex_rebind_idx;
ALTER TABLE public.workspace_engine_settings DROP COLUMN IF EXISTS codex_auth_mode;
ALTER TABLE public.agent_engine_attempts DROP COLUMN IF EXISTS accepted_at;
ALTER TABLE public.agent_engine_attempts DROP COLUMN IF EXISTS auth_mode_generation;
ALTER TABLE public.agent_engine_runs DROP COLUMN IF EXISTS auth_mode_generation;

CREATE OR REPLACE FUNCTION public.set_workspace_default_engine(
  p_workspace_id uuid,
  p_engine_id text,
  p_auth_mode text DEFAULT 'managed'
) RETURNS public.workspace_engine_settings
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_row public.workspace_engine_settings;
BEGIN
  IF NOT public.is_workspace_owner(p_workspace_id, auth.uid()) THEN
    RAISE EXCEPTION 'workspace default engine requires owner' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.workspace_engine_settings(workspace_id, default_engine_id, default_auth_mode, updated_by)
  VALUES (p_workspace_id, p_engine_id, p_auth_mode, auth.uid())
  ON CONFLICT (workspace_id) DO UPDATE
    SET default_engine_id = EXCLUDED.default_engine_id,
        default_auth_mode = EXCLUDED.default_auth_mode,
        updated_by = EXCLUDED.updated_by,
        updated_at = now()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.set_workspace_default_engine(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_workspace_default_engine(uuid, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_workspace_default_engine(uuid, text, text) TO authenticated;

DROP FUNCTION IF EXISTS public.start_agent_engine_attempt(uuid, text, text, bigint);
CREATE OR REPLACE FUNCTION public.start_agent_engine_attempt(
  p_run_id uuid, p_attempt_key text
) RETURNS public.agent_engine_attempts
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_row public.agent_engine_attempts;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine attempt requires service role' USING ERRCODE = '42501';
  END IF;
  IF p_attempt_key IS NULL OR length(p_attempt_key) NOT BETWEEN 1 AND 256 THEN
    RAISE EXCEPTION 'invalid attempt key' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.agent_engine_attempts(run_id, attempt_key)
  VALUES (p_run_id, p_attempt_key)
  ON CONFLICT (run_id, attempt_key) DO NOTHING
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'attempt key already exists' USING ERRCODE = '23505';
  END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.start_agent_engine_attempt(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_agent_engine_attempt(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.transition_agent_engine_attempt(
  p_attempt_id uuid, p_status text
) RETURNS public.agent_engine_attempts
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_row public.agent_engine_attempts;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine attempt transition requires service role' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('queued','running','waiting','cancel_requested','completed','failed','cancelled')
     OR p_status IS NULL THEN
    RAISE EXCEPTION 'invalid attempt status' USING ERRCODE = '22023';
  END IF;
  SELECT a.* INTO v_row FROM public.agent_engine_attempts AS a
    WHERE a.id = p_attempt_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine attempt not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_row.status IN ('completed','failed','cancelled') THEN
    IF v_row.status <> p_status THEN
      RAISE EXCEPTION 'terminal engine attempt is immutable' USING ERRCODE = '23P01';
    END IF;
    RETURN v_row;
  END IF;
  IF NOT (CASE v_row.status
    WHEN 'queued' THEN p_status IN ('running','cancel_requested','failed','cancelled')
    WHEN 'running' THEN p_status IN ('waiting','cancel_requested','completed','failed','cancelled')
    WHEN 'waiting' THEN p_status IN ('running','cancel_requested','failed','cancelled')
    WHEN 'cancel_requested' THEN p_status IN ('completed','failed','cancelled')
    ELSE FALSE
  END) THEN
    RAISE EXCEPTION 'invalid engine attempt transition: % -> %', v_row.status, p_status
      USING ERRCODE = '23P01';
  END IF;
  UPDATE public.agent_engine_attempts AS a SET
    status = p_status,
    updated_at = now(),
    terminal_at = CASE WHEN p_status IN ('completed','failed','cancelled')
      THEN COALESCE(a.terminal_at, now()) ELSE NULL END
    WHERE a.id = p_attempt_id RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.transition_agent_engine_attempt(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.transition_agent_engine_attempt(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.append_agent_engine_lifecycle_event(
  p_run_id uuid, p_attempt_id uuid, p_payload jsonb
) RETURNS public.agent_engine_events
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_sequence integer;
        v_row public.agent_engine_events;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine lifecycle append requires service role' USING ERRCODE = '42501';
  END IF;
  IF p_payload IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object'
     OR p_payload->>'type' IS DISTINCT FROM 'lifecycle'
     OR p_payload->>'source_type' NOT IN ('status','approval','error')
     OR p_payload->>'source_type' IS NULL
     OR (p_payload - 'type' - 'source_type' - 'status') <> '{}'::jsonb
     OR (p_payload->>'source_type' = 'status' AND (
       p_payload->>'status' NOT IN ('queued','running','waiting','cancel_requested','completed','failed','cancelled')
       OR p_payload->>'status' IS NULL
     ))
     OR (p_payload->>'source_type' <> 'status' AND p_payload ? 'status') THEN
    RAISE EXCEPTION 'event payload is not bounded lifecycle metadata' USING ERRCODE = '22023';
  END IF;
  PERFORM 1 FROM public.agent_engine_runs AS r WHERE r.id = p_run_id FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM public.agent_engine_attempts AS a
     WHERE a.id = p_attempt_id AND a.run_id = p_run_id
  ) THEN
    RAISE EXCEPTION 'attempt does not belong to binding' USING ERRCODE = '42501';
  END IF;
  SELECT COALESCE(MAX(e.sequence), 0) + 1 INTO v_sequence
    FROM public.agent_engine_events AS e WHERE e.run_id = p_run_id;
  INSERT INTO public.agent_engine_events(run_id, attempt_id, event_id, sequence, payload)
  VALUES (p_run_id, p_attempt_id, 'engine-event-' || v_sequence::text, v_sequence, p_payload)
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.append_agent_engine_lifecycle_event(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.append_agent_engine_lifecycle_event(uuid, uuid, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.save_agent_engine_recovery_checkpoint(
  p_run_id uuid, p_checkpoint jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine recovery requires service role' USING ERRCODE = '42501';
  END IF;
  IF p_checkpoint IS NULL OR jsonb_typeof(p_checkpoint) IS DISTINCT FROM 'object'
     OR octet_length(p_checkpoint::text) > 16384 THEN
    RAISE EXCEPTION 'invalid recovery checkpoint' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.agent_engine_recovery_checkpoints(run_id, checkpoint)
  VALUES (p_run_id, p_checkpoint)
  ON CONFLICT (run_id) DO UPDATE SET checkpoint = EXCLUDED.checkpoint, updated_at = now();
END;
$$;
REVOKE ALL ON FUNCTION public.save_agent_engine_recovery_checkpoint(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_agent_engine_recovery_checkpoint(uuid, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.bind_agent_engine_run(
  p_workspace_id uuid,
  p_execution_kind text,
  p_conversation_id uuid,
  p_routine_id text,
  p_routine_run_id text,
  p_created_by uuid
) RETURNS public.agent_engine_runs
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_row public.agent_engine_runs;
BEGIN
  IF auth.role() = 'service_role' THEN
    IF NOT public.is_workspace_member(p_workspace_id, p_created_by) THEN
      RAISE EXCEPTION 'workspace creator membership required' USING ERRCODE = '42501';
    END IF;
  ELSIF NOT public.is_workspace_member(p_workspace_id, auth.uid()) THEN
    RAISE EXCEPTION 'workspace membership required' USING ERRCODE = '42501';
  END IF;
  IF auth.role() <> 'service_role' AND p_created_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'created_by must match authenticated user' USING ERRCODE = '42501';
  END IF;
  IF p_conversation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.conversations
     WHERE id = p_conversation_id AND workspace_id = p_workspace_id
       AND user_id = p_created_by
  ) THEN
    RAISE EXCEPTION 'conversation ownership required' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.agent_engine_runs(
    workspace_id, execution_kind, conversation_id, routine_id, routine_run_id,
    engine_id, auth_mode, adapter_version, status, created_by
  )
  SELECT p_workspace_id, p_execution_kind, p_conversation_id, p_routine_id,
         p_routine_run_id, COALESCE(s.default_engine_id, 'claude-code'),
         COALESCE(s.default_auth_mode, 'managed'),
         CASE COALESCE(s.default_engine_id, 'claude-code')
           WHEN 'codex' THEN 'codex-v1'
           WHEN 'claude-code' THEN 'claude-code-v1'
           ELSE 'registry-pending'
         END,
         'queued', p_created_by
    FROM (SELECT default_engine_id, default_auth_mode
            FROM public.workspace_engine_settings
           WHERE workspace_id = p_workspace_id) AS s
  RIGHT JOIN (SELECT 1) AS sentinel ON true
  RETURNING * INTO v_row;
  IF p_conversation_id IS NOT NULL THEN
    PERFORM set_config('soleur.engine_binding_rpc', '1', true);
    UPDATE public.conversations SET engine_binding_state = 'bound'
     WHERE id = p_conversation_id AND user_id = p_created_by;
  END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) TO authenticated, service_role;

COMMIT;
