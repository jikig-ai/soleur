-- 145_codex_auth_mode_rebind.sql
-- An explicit owner mode change can rebind existing Codex conversations. The
-- transaction also invalidates recovery state from the previous account.
-- LAWFUL_BASIS: GDPR Art. 6(1)(b) for selected Codex execution and Art. 6(1)(f)
--   for bounded operational lineage, unchanged from migration 138.
-- RETENTION: accepted_at follows the existing attempt/run retention and cascade
--   erasure rules established by migrations 138 and 143.
BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';

ALTER TABLE public.agent_engine_attempts
  ADD COLUMN accepted_at timestamptz;
ALTER TABLE public.workspace_engine_settings
  ADD COLUMN codex_auth_mode text NOT NULL DEFAULT 'managed'
    CHECK (codex_auth_mode IN ('managed', 'api-key'));

UPDATE public.workspace_engine_settings AS settings
   SET codex_auth_mode = CASE
     WHEN settings.default_engine_id = 'codex' THEN settings.default_auth_mode
     ELSE (
       SELECT r.auth_mode
         FROM public.agent_engine_runs AS r
        WHERE r.workspace_id = settings.workspace_id
          AND r.execution_kind = 'conversation'
          AND r.engine_id = 'codex'
          AND r.auth_mode IN ('managed', 'api-key')
        ORDER BY r.created_at DESC
        LIMIT 1
     )
   END
 WHERE settings.default_engine_id = 'codex'
    OR EXISTS (
      SELECT 1
        FROM public.agent_engine_runs AS r
       WHERE r.workspace_id = settings.workspace_id
         AND r.execution_kind = 'conversation'
         AND r.engine_id = 'codex'
         AND r.auth_mode IN ('managed', 'api-key')
    );

CREATE INDEX IF NOT EXISTS agent_engine_runs_codex_rebind_idx
  ON public.agent_engine_runs (workspace_id, auth_mode)
  WHERE execution_kind = 'conversation' AND engine_id = 'codex';

CREATE OR REPLACE FUNCTION public.set_workspace_default_engine(
  p_workspace_id uuid,
  p_engine_id text,
  p_auth_mode text DEFAULT 'managed',
  p_apply_to_existing_codex_conversations boolean DEFAULT false,
  p_expected_affected_count integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_setting public.workspace_engine_settings;
  v_affected integer := 0;
  v_checkpoints integer := 0;
BEGIN
  IF NOT public.is_workspace_owner(p_workspace_id, auth.uid()) THEN
    RAISE EXCEPTION 'workspace default engine requires owner' USING ERRCODE = '42501';
  END IF;
  IF p_engine_id IS NULL OR length(p_engine_id) NOT BETWEEN 1 AND 128
     OR p_auth_mode IS NULL OR length(p_auth_mode) NOT BETWEEN 1 AND 64 THEN
    RAISE EXCEPTION 'unsupported engine or auth mode' USING ERRCODE = '22023';
  END IF;
  IF p_apply_to_existing_codex_conversations
     AND (p_engine_id <> 'codex' OR p_auth_mode NOT IN ('managed', 'api-key')) THEN
    RAISE EXCEPTION 'existing conversation update requires a Codex mode' USING ERRCODE = '22023';
  END IF;
  IF p_apply_to_existing_codex_conversations
     AND (p_expected_affected_count IS NULL OR p_expected_affected_count < 0) THEN
    RAISE EXCEPTION 'expected affected conversation count is required' USING ERRCODE = '22023';
  END IF;

  -- Serialize with run creation and other workspace setting changes, including
  -- the first settings write where no settings row exists yet.
  PERFORM 1 FROM public.workspaces AS w WHERE w.id = p_workspace_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workspace not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_setting
    FROM public.workspace_engine_settings
   WHERE workspace_id = p_workspace_id
   FOR UPDATE;
  IF p_apply_to_existing_codex_conversations THEN
    SELECT count(*)::integer INTO v_affected
      FROM public.agent_engine_runs AS r
     WHERE r.workspace_id = p_workspace_id
       AND r.execution_kind = 'conversation'
       AND r.engine_id = 'codex'
       AND r.auth_mode IS DISTINCT FROM p_auth_mode;
    IF v_affected IS DISTINCT FROM p_expected_affected_count THEN
      RAISE EXCEPTION 'affected Codex conversation count changed' USING ERRCODE = '40001';
    END IF;
  END IF;

  INSERT INTO public.workspace_engine_settings(workspace_id, default_engine_id, default_auth_mode, codex_auth_mode, updated_by)
  VALUES (
    p_workspace_id,
    CASE WHEN p_apply_to_existing_codex_conversations
      THEN COALESCE(v_setting.default_engine_id, 'claude-code') ELSE p_engine_id END,
    CASE WHEN p_apply_to_existing_codex_conversations
      THEN COALESCE(v_setting.default_auth_mode, 'managed') ELSE p_auth_mode END,
    CASE WHEN p_engine_id = 'codex' OR p_apply_to_existing_codex_conversations THEN p_auth_mode ELSE 'managed' END,
    auth.uid()
  )
  ON CONFLICT (workspace_id) DO UPDATE
    SET default_engine_id = CASE WHEN p_apply_to_existing_codex_conversations
          THEN public.workspace_engine_settings.default_engine_id ELSE EXCLUDED.default_engine_id END,
        default_auth_mode = CASE WHEN p_apply_to_existing_codex_conversations
          THEN public.workspace_engine_settings.default_auth_mode ELSE EXCLUDED.default_auth_mode END,
        codex_auth_mode = CASE WHEN p_engine_id = 'codex' OR p_apply_to_existing_codex_conversations THEN p_auth_mode ELSE public.workspace_engine_settings.codex_auth_mode END,
        updated_by = EXCLUDED.updated_by,
        updated_at = now()
  RETURNING * INTO v_setting;

  IF p_apply_to_existing_codex_conversations THEN
    WITH changed AS (
      UPDATE public.agent_engine_runs AS r
         SET auth_mode = p_auth_mode,
             auth_mode_generation = r.auth_mode_generation + 1
       WHERE r.workspace_id = p_workspace_id
         AND r.execution_kind = 'conversation'
         AND r.engine_id = 'codex'
         AND r.auth_mode IS DISTINCT FROM p_auth_mode
       RETURNING r.id
    ), deleted AS (
      DELETE FROM public.agent_engine_recovery_checkpoints AS c
       USING changed AS x
       WHERE c.run_id = x.id
       RETURNING c.run_id
    )
    SELECT (SELECT count(*)::integer FROM changed),
           (SELECT count(*)::integer FROM deleted)
      INTO v_affected, v_checkpoints;
  END IF;

  RETURN jsonb_build_object(
    'defaultEngineId', v_setting.default_engine_id,
    'defaultAuthMode', v_setting.default_auth_mode,
    'affectedConversationCount', v_affected,
    'deletedCheckpointCount', v_checkpoints
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_workspace_default_engine(uuid, text, text, boolean, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_workspace_default_engine(uuid, text, text, boolean, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_workspace_default_engine(uuid, text, text, boolean, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.count_codex_conversation_rebinds(
  p_workspace_id uuid, p_auth_mode text
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_count integer;
BEGIN
  IF NOT public.is_workspace_owner(p_workspace_id, auth.uid()) THEN
    RAISE EXCEPTION 'Codex conversation count requires owner' USING ERRCODE = '42501';
  END IF;
  IF p_auth_mode IS NULL OR p_auth_mode NOT IN ('managed', 'api-key') THEN
    RAISE EXCEPTION 'unsupported Codex auth mode' USING ERRCODE = '22023';
  END IF;
  SELECT count(*)::integer INTO v_count
    FROM public.agent_engine_runs AS r
   WHERE r.workspace_id = p_workspace_id
     AND r.execution_kind = 'conversation'
     AND r.engine_id = 'codex'
     AND r.auth_mode IS DISTINCT FROM p_auth_mode;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.count_codex_conversation_rebinds(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.count_codex_conversation_rebinds(uuid, text) TO authenticated;

DROP FUNCTION public.start_agent_engine_attempt(uuid, text);
CREATE FUNCTION public.start_agent_engine_attempt(
  p_run_id uuid, p_attempt_key text, p_expected_auth_mode text, p_expected_generation bigint
) RETURNS public.agent_engine_attempts
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.agent_engine_attempts;
  v_generation bigint;
  v_auth_mode text;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine attempt requires service role' USING ERRCODE = '42501';
  END IF;
  IF p_attempt_key IS NULL OR length(p_attempt_key) NOT BETWEEN 1 AND 256 THEN
    RAISE EXCEPTION 'invalid attempt key' USING ERRCODE = '22023';
  END IF;
  SELECT r.auth_mode_generation, r.auth_mode INTO v_generation, v_auth_mode
    FROM public.agent_engine_runs AS r WHERE r.id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine run not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_generation IS DISTINCT FROM p_expected_generation
     OR v_auth_mode IS DISTINCT FROM p_expected_auth_mode THEN
    RAISE EXCEPTION 'Codex conversation binding changed' USING ERRCODE = '55000';
  END IF;
  INSERT INTO public.agent_engine_attempts(run_id, attempt_key, auth_mode_generation)
  VALUES (p_run_id, p_attempt_key, v_generation)
  ON CONFLICT (run_id, attempt_key) DO NOTHING
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'attempt key already exists' USING ERRCODE = '23505';
  END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.start_agent_engine_attempt(uuid, text, text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_agent_engine_attempt(uuid, text, text, bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.assert_agent_engine_attempt_generation(
  p_attempt_id uuid
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_attempt_generation bigint;
  v_run_generation bigint;
  v_run_id uuid;
  v_accepted_at timestamptz;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine attempt validation requires service role' USING ERRCODE = '42501';
  END IF;
  SELECT a.run_id, a.auth_mode_generation
    INTO v_run_id, v_attempt_generation
    FROM public.agent_engine_attempts AS a
   WHERE a.id = p_attempt_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine attempt not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT r.auth_mode_generation INTO v_run_generation
    FROM public.agent_engine_runs AS r
   WHERE r.id = v_run_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine run not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_attempt_generation IS DISTINCT FROM v_run_generation THEN
    RAISE EXCEPTION 'engine attempt auth mode is stale' USING ERRCODE = '55000';
  END IF;
  -- This RPC is the transport admission point. A later mode switch may not
  -- revoke the response to this accepted request, but any subsequent request
  -- admission still compares generations and therefore rejects stale retries.
  UPDATE public.agent_engine_attempts AS a
     SET accepted_at = COALESCE(a.accepted_at, now())
   WHERE a.id = p_attempt_id
     AND a.auth_mode_generation = v_run_generation
  RETURNING a.accepted_at INTO v_accepted_at;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine attempt auth mode is stale' USING ERRCODE = '55000';
  END IF;
  RETURN v_run_generation;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_agent_engine_attempt_generation(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assert_agent_engine_attempt_generation(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.transition_agent_engine_attempt(
  p_attempt_id uuid, p_status text
) RETURNS public.agent_engine_attempts
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.agent_engine_attempts;
  v_run_generation bigint;
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
  SELECT r.auth_mode_generation INTO v_run_generation
    FROM public.agent_engine_runs AS r WHERE r.id = v_row.run_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine run not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_row.accepted_at IS NULL
     AND v_row.auth_mode_generation IS DISTINCT FROM v_run_generation
     AND p_status NOT IN ('failed','cancelled') THEN
    RAISE EXCEPTION 'engine attempt auth mode is stale' USING ERRCODE = '55000';
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
DECLARE
  v_sequence integer;
  v_row public.agent_engine_events;
  v_attempt public.agent_engine_attempts;
  v_run_generation bigint;
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
  SELECT r.auth_mode_generation INTO v_run_generation
    FROM public.agent_engine_runs AS r WHERE r.id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine run not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT a.* INTO v_attempt FROM public.agent_engine_attempts AS a
   WHERE a.id = p_attempt_id AND a.run_id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'attempt does not belong to binding' USING ERRCODE = '42501';
  END IF;
  IF v_attempt.accepted_at IS NULL
     AND v_attempt.auth_mode_generation IS DISTINCT FROM v_run_generation
     AND NOT (p_payload->>'source_type' = 'status'
       AND p_payload->>'status' IN ('failed','cancelled')) THEN
    RAISE EXCEPTION 'engine attempt auth mode is stale' USING ERRCODE = '55000';
  END IF;
  SELECT COALESCE(MAX(e.sequence), 0) + 1 INTO v_sequence
    FROM public.agent_engine_events AS e WHERE e.run_id = p_run_id;
  INSERT INTO public.agent_engine_events(run_id, attempt_id, event_id, sequence, payload)
  VALUES (p_run_id, p_attempt_id, 'engine-event-' || v_sequence::text, v_sequence, p_payload)
  RETURNING * INTO v_row;
  IF p_payload->>'source_type' = 'status'
     AND p_payload->>'status' IN ('completed','failed','cancelled') THEN
    IF v_attempt.status IN ('completed','failed','cancelled')
       AND v_attempt.status IS DISTINCT FROM p_payload->>'status' THEN
      RAISE EXCEPTION 'terminal engine attempt is immutable' USING ERRCODE = '23P01';
    END IF;
    IF v_attempt.status NOT IN ('running','waiting','cancel_requested','completed','failed','cancelled') THEN
      RAISE EXCEPTION 'invalid terminal engine attempt transition' USING ERRCODE = '23P01';
    END IF;
    UPDATE public.agent_engine_attempts AS a SET
      status = p_payload->>'status',
      updated_at = now(),
      terminal_at = COALESCE(a.terminal_at, now())
      WHERE a.id = p_attempt_id;
  END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.append_agent_engine_lifecycle_event(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.append_agent_engine_lifecycle_event(uuid, uuid, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.save_agent_engine_recovery_checkpoint(
  p_run_id uuid, p_attempt_id uuid, p_checkpoint jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_run_generation bigint;
  v_attempt_generation bigint;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine recovery requires service role' USING ERRCODE = '42501';
  END IF;
  IF p_checkpoint IS NULL OR jsonb_typeof(p_checkpoint) IS DISTINCT FROM 'object'
     OR octet_length(p_checkpoint::text) > 16384 THEN
    RAISE EXCEPTION 'invalid recovery checkpoint' USING ERRCODE = '22023';
  END IF;
  SELECT r.auth_mode_generation INTO v_run_generation
    FROM public.agent_engine_runs AS r WHERE r.id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine run not found' USING ERRCODE = 'P0002';
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
REVOKE ALL ON FUNCTION public.save_agent_engine_recovery_checkpoint(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_agent_engine_recovery_checkpoint(uuid, uuid, jsonb) TO service_role;

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
  -- Pair with the owner's FOR UPDATE lock so a conversation cannot bind to
  -- the old mode after the owner's rebinding transaction has scanned runs.
  PERFORM 1 FROM public.workspaces AS w WHERE w.id = p_workspace_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workspace not found' USING ERRCODE = 'P0002';
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
         CASE
           WHEN p_execution_kind = 'conversation'
            AND COALESCE(s.default_engine_id, 'claude-code') = 'codex'
             THEN s.codex_auth_mode
           ELSE COALESCE(s.default_auth_mode, 'managed')
         END,
         CASE COALESCE(s.default_engine_id, 'claude-code')
           WHEN 'codex' THEN 'codex-v1'
           WHEN 'claude-code' THEN 'claude-code-v1'
           ELSE 'registry-pending'
         END,
         'queued', p_created_by
    FROM (SELECT default_engine_id, default_auth_mode, codex_auth_mode
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
