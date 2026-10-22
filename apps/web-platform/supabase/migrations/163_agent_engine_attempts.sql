-- 143_agent_engine_attempts.sql
-- A conversation run is an immutable engine binding. Each turn is a separate
-- attempt; native recovery data lives behind service-role-only RPCs.
-- LAWFUL_BASIS: Art. 6(1)(b), execution and recovery of the requested turn.
-- RETENTION: Cascades with the bound run/conversation/workspace; account
-- deletion also purges native checkpoints before anonymising retained lineage.
BEGIN;

DO $$ BEGIN
  IF to_regclass('public.agent_engine_runs') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.agent_engine_runs must exist before 143';
  END IF;
  IF to_regclass('public.agent_engine_events') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.agent_engine_events must exist before 143';
  END IF;
END $$;

CREATE TABLE public.agent_engine_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES public.agent_engine_runs(id) ON DELETE CASCADE,
  attempt_key text NOT NULL CHECK (length(attempt_key) BETWEEN 1 AND 256),
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued','running','waiting','cancel_requested','completed','failed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  terminal_at timestamptz,
  UNIQUE (run_id, attempt_key),
  CONSTRAINT agent_engine_attempt_terminal_chk CHECK (
    (status IN ('completed','failed','cancelled')) = (terminal_at IS NOT NULL)
  )
);

ALTER TABLE public.agent_engine_events
  ADD COLUMN attempt_id uuid REFERENCES public.agent_engine_attempts(id) ON DELETE CASCADE;

CREATE INDEX agent_engine_attempts_run_created_idx
  ON public.agent_engine_attempts(run_id, created_at DESC);

-- No member-readable relation may contain native handles, cursors, provider
-- idempotency values, or usage provenance. This table has no SELECT policy.
CREATE TABLE public.agent_engine_recovery_checkpoints (
  run_id uuid PRIMARY KEY REFERENCES public.agent_engine_runs(id) ON DELETE CASCADE,
  checkpoint jsonb NOT NULL CHECK (jsonb_typeof(checkpoint) = 'object'
    AND octet_length(checkpoint::text) <= 16384),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Attempt keys may encode application retry identity, so even this status
-- table is private to the service boundary.
REVOKE ALL ON TABLE public.agent_engine_attempts FROM anon, authenticated;
REVOKE ALL ON TABLE public.agent_engine_recovery_checkpoints FROM anon, authenticated;
ALTER TABLE public.agent_engine_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_engine_recovery_checkpoints ENABLE ROW LEVEL SECURITY;

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
  -- The run is an immutable binding. Its terminal status is legacy state and
  -- does not prevent subsequent turns on the same conversation.
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

-- Serialize sequence allocation on the immutable binding row. The ledger
-- records lifecycle classes only, never text or native provider identities.
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

CREATE OR REPLACE FUNCTION public.get_agent_engine_recovery_checkpoint(
  p_run_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_checkpoint jsonb;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'engine recovery requires service role' USING ERRCODE = '42501';
  END IF;
  SELECT c.checkpoint INTO v_checkpoint
    FROM public.agent_engine_recovery_checkpoints AS c WHERE c.run_id = p_run_id;
  RETURN v_checkpoint;
END;
$$;
REVOKE ALL ON FUNCTION public.get_agent_engine_recovery_checkpoint(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_agent_engine_recovery_checkpoint(uuid) TO service_role;

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

COMMIT;
