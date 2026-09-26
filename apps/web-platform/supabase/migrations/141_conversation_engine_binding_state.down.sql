BEGIN;

DROP TRIGGER IF EXISTS conversations_engine_binding_state_insert ON public.conversations;
DROP TRIGGER IF EXISTS conversations_engine_binding_state_immutable ON public.conversations;
DROP FUNCTION IF EXISTS public.guard_conversation_engine_binding_state();
ALTER TABLE public.conversations DROP COLUMN IF EXISTS engine_binding_state;

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
    SELECT 1
      FROM public.conversations
     WHERE id = p_conversation_id
       AND workspace_id = p_workspace_id
       AND user_id = p_created_by
  ) THEN
    RAISE EXCEPTION 'conversation does not belong to workspace' USING ERRCODE = '42501';
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
    FROM (SELECT default_engine_id, default_auth_mode FROM public.workspace_engine_settings
           WHERE workspace_id = p_workspace_id) s
  RIGHT JOIN (SELECT 1) sentinel ON true
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) TO authenticated, service_role;

COMMIT;
