-- 057_byok_audit_workspace_id_rpcs.down.sql — restore 5-arg signatures.
--
-- WARNING: Rolling this back leaves the JS callers (cost-writer.ts +
-- agent-runner.ts + cc-dispatcher.ts) passing p_workspace_id to a 5-arg
-- function — postgrest will reject with PGRST202 "Could not find the
-- function". Roll back the application deploy FIRST, then this migration.

BEGIN;

DROP FUNCTION IF EXISTS public.write_byok_audit(uuid, uuid, uuid, text, int, int);
DROP FUNCTION IF EXISTS public.record_byok_use_and_check_cap(uuid, uuid, uuid, text, int, int);

-- Restore migration-037 shape.
CREATE OR REPLACE FUNCTION public.write_byok_audit(
  p_invocation_id   uuid,
  p_founder_id      uuid,
  p_agent_role      text,
  p_token_count     int,
  p_unit_cost_cents int
) RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  INSERT INTO public.audit_byok_use(
    invocation_id, founder_id, agent_role, token_count, unit_cost_cents
  )
  VALUES (
    p_invocation_id, p_founder_id, p_agent_role, p_token_count, p_unit_cost_cents
  );
$$;

REVOKE ALL ON FUNCTION public.write_byok_audit(uuid, uuid, text, int, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_byok_audit(uuid, uuid, text, int, int)
  TO service_role;

-- Restore migration-046 shape.
CREATE OR REPLACE FUNCTION public.record_byok_use_and_check_cap(
  p_invocation_id   uuid,
  p_founder_id      uuid,
  p_agent_role      text,
  p_token_count     int,
  p_unit_cost_cents int
) RETURNS TABLE(cumulative_cents int, kill_tripped boolean)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_cap        int;
  v_paused_at  timestamptz;
  v_total      int;
  v_tripped    boolean := false;
BEGIN
  SELECT runtime_cost_cap_cents, runtime_paused_at
    INTO v_cap, v_paused_at
    FROM public.users
   WHERE id = p_founder_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'record_byok_use_and_check_cap: founder % not found', p_founder_id
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, agent_role, token_count, unit_cost_cents
  ) VALUES (
    p_invocation_id, p_founder_id, p_agent_role, p_token_count, p_unit_cost_cents
  );

  SELECT COALESCE(SUM(token_count * unit_cost_cents), 0)::int
    INTO v_total
    FROM public.audit_byok_use
   WHERE founder_id = p_founder_id
     AND ts > now() - interval '1 hour';

  IF v_paused_at IS NULL AND v_total > v_cap THEN
    UPDATE public.users
       SET runtime_paused_at = now()
     WHERE id = p_founder_id
       AND runtime_paused_at IS NULL;
    v_tripped := true;
  END IF;

  cumulative_cents := v_total;
  kill_tripped     := v_tripped;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, text, int, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, text, int, int)
  TO service_role;

COMMIT;
