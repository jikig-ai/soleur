-- 138_agent_engine_runs.sql
-- Live engine dispatch authority. routine_runs remains the terminal-only WORM log.

BEGIN;

CREATE TABLE IF NOT EXISTS public.workspace_engine_settings (
  workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE CASCADE,
  default_engine_id text NOT NULL,
  updated_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.agent_engine_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  execution_kind text NOT NULL CHECK (execution_kind IN ('conversation', 'routine')),
  conversation_id uuid NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  routine_id text NULL,
  routine_run_id text NULL,
  engine_id text NOT NULL,
  auth_mode text NOT NULL,
  adapter_version text NOT NULL,
  status text NOT NULL CHECK (status IN ('queued','running','waiting','cancel_requested','completed','failed','cancelled')),
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  terminal_at timestamptz NULL,
  CONSTRAINT agent_engine_runs_execution_chk CHECK (
    (execution_kind = 'conversation' AND conversation_id IS NOT NULL AND routine_id IS NULL AND routine_run_id IS NULL)
    OR (execution_kind = 'routine' AND conversation_id IS NULL AND routine_id IS NOT NULL AND routine_run_id IS NOT NULL)
  ),
  CONSTRAINT agent_engine_runs_terminal_chk CHECK (
    (status IN ('completed','failed','cancelled')) = (terminal_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS agent_engine_runs_conversation_uniq
  ON public.agent_engine_runs (conversation_id) WHERE execution_kind = 'conversation';
CREATE UNIQUE INDEX IF NOT EXISTS agent_engine_runs_routine_uniq
  ON public.agent_engine_runs (routine_id, routine_run_id) WHERE execution_kind = 'routine';
CREATE INDEX IF NOT EXISTS agent_engine_runs_workspace_created_idx
  ON public.agent_engine_runs (workspace_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.agent_engine_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id uuid NOT NULL REFERENCES public.agent_engine_runs(id) ON DELETE CASCADE,
  event_id text NOT NULL,
  sequence integer NOT NULL CHECK (sequence > 0),
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (run_id, event_id),
  UNIQUE (run_id, sequence)
);

ALTER TABLE public.workspace_engine_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_engine_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_engine_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY workspace_engine_settings_member_select ON public.workspace_engine_settings
  FOR SELECT TO authenticated USING (public.is_workspace_member(workspace_id, auth.uid()));
CREATE POLICY agent_engine_runs_member_select ON public.agent_engine_runs
  FOR SELECT TO authenticated USING (public.is_workspace_member(workspace_id, auth.uid()));
CREATE POLICY agent_engine_events_member_select ON public.agent_engine_events
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.agent_engine_runs r
      WHERE r.id = run_id AND public.is_workspace_member(r.workspace_id, auth.uid()))
  );

CREATE OR REPLACE FUNCTION public.set_workspace_default_engine(
  p_workspace_id uuid,
  p_engine_id text
) RETURNS public.workspace_engine_settings
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_row public.workspace_engine_settings;
BEGIN
  IF NOT public.is_workspace_owner(p_workspace_id, auth.uid()) THEN
    RAISE EXCEPTION 'workspace default engine requires owner' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.workspace_engine_settings(workspace_id, default_engine_id, updated_by)
  VALUES (p_workspace_id, p_engine_id, auth.uid())
  ON CONFLICT (workspace_id) DO UPDATE
    SET default_engine_id = EXCLUDED.default_engine_id,
        updated_by = EXCLUDED.updated_by,
        updated_at = now()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.set_workspace_default_engine(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_workspace_default_engine(uuid, text) TO authenticated;

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
  IF NOT public.is_workspace_member(p_workspace_id, auth.uid()) THEN
    RAISE EXCEPTION 'workspace membership required' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.agent_engine_runs(
    workspace_id, execution_kind, conversation_id, routine_id, routine_run_id,
    engine_id, auth_mode, adapter_version, status, created_by
  )
  SELECT p_workspace_id, p_execution_kind, p_conversation_id, p_routine_id,
         p_routine_run_id, COALESCE(s.default_engine_id, 'claude-code'),
         'unresolved', 'registry-pending', 'queued', p_created_by
    FROM (SELECT default_engine_id FROM public.workspace_engine_settings
           WHERE workspace_id = p_workspace_id) s
  RIGHT JOIN (SELECT 1) sentinel ON true
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) TO service_role;

COMMIT;
