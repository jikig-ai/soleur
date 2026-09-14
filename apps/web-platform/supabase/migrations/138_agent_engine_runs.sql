-- 138_agent_engine_runs.sql
-- Live engine dispatch authority. routine_runs remains the terminal-only WORM log.

BEGIN;

CREATE TABLE IF NOT EXISTS public.workspace_engine_settings (
  workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE CASCADE,
  default_engine_id text NOT NULL,
  default_auth_mode text NOT NULL DEFAULT 'managed',
  updated_by uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT,
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
  created_by uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT,
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

-- Idempotent event append: an exact retry returns the existing row, while
-- reusing an event key with a different sequence or payload is rejected.
CREATE OR REPLACE FUNCTION public.append_agent_engine_event(
  p_run_id uuid,
  p_event_id text,
  p_sequence integer,
  p_payload jsonb
) RETURNS public.agent_engine_events
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_row public.agent_engine_events;
BEGIN
  IF auth.role() <> 'service_role' AND NOT EXISTS (
    SELECT 1 FROM public.agent_engine_runs r
    WHERE r.id = p_run_id AND public.is_workspace_member(r.workspace_id, auth.uid())
  ) THEN
    RAISE EXCEPTION 'workspace membership required' USING ERRCODE = '42501';
  END IF;
  SELECT e.* INTO v_row
    FROM public.agent_engine_events e
   WHERE e.run_id = p_run_id AND e.event_id = p_event_id;
  IF FOUND THEN
    IF v_row.sequence IS DISTINCT FROM p_sequence OR v_row.payload IS DISTINCT FROM p_payload THEN
      RAISE EXCEPTION 'event key already maps to a different event' USING ERRCODE = '23P01';
    END IF;
    RETURN v_row;
  END IF;
  INSERT INTO public.agent_engine_events(run_id, event_id, sequence, payload)
  VALUES (p_run_id, p_event_id, p_sequence, p_payload)
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.append_agent_engine_event(uuid, text, integer, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.append_agent_engine_event(uuid, text, integer, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.append_agent_engine_event(uuid, text, integer, jsonb) TO authenticated, service_role;

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
  INSERT INTO public.agent_engine_runs(
    workspace_id, execution_kind, conversation_id, routine_id, routine_run_id,
    engine_id, auth_mode, adapter_version, status, created_by
  )
  SELECT p_workspace_id, p_execution_kind, p_conversation_id, p_routine_id,
         p_routine_run_id, COALESCE(s.default_engine_id, 'claude-code'),
         COALESCE(s.default_auth_mode, 'managed'), 'registry-pending', 'queued', p_created_by
    FROM (SELECT default_engine_id, default_auth_mode FROM public.workspace_engine_settings
           WHERE workspace_id = p_workspace_id) s
  RIGHT JOIN (SELECT 1) sentinel ON true
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_agent_engine_run(uuid, text, uuid, text, text, uuid) TO authenticated, service_role;

-- Account erasure keeps operational engine lineage while severing user identity.
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
    SET updated_by = NULL
    WHERE updated_by = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_count := v_rows;
  UPDATE public.agent_engine_runs
    SET created_by = NULL
    WHERE created_by = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_count := v_count + v_rows;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_agent_engine_data(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.anonymise_agent_engine_data(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_agent_engine_data(uuid) TO service_role;

COMMIT;
