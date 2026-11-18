-- 148_codex_lifecycle_lock_order.down.sql
-- Restore the transition and lifecycle functions from migrations 145 and 147.
BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';
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
  SELECT a.* INTO v_attempt FROM public.agent_engine_attempts AS a
   WHERE a.id = p_attempt_id AND a.run_id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'attempt does not belong to binding' USING ERRCODE = '42501';
  END IF;
  SELECT r.auth_mode_generation INTO v_run_generation
    FROM public.agent_engine_runs AS r WHERE r.id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine run not found' USING ERRCODE = 'P0002';
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
     AND p_payload->>'status' IS DISTINCT FROM v_attempt.status THEN
    -- Reuse the attempt state machine in this transaction, so lifecycle rows
    -- and current status advance together for running, waiting, cancellation,
    -- and terminal outcomes.
    PERFORM public.transition_agent_engine_attempt(p_attempt_id, p_payload->>'status');
  END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.append_agent_engine_lifecycle_event(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.append_agent_engine_lifecycle_event(uuid, uuid, jsonb) TO service_role;

COMMIT;
