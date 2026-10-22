-- 147_codex_lifecycle_state_sync.down.sql
-- Restore migration 146 lifecycle status behavior.
BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';

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


COMMIT;
