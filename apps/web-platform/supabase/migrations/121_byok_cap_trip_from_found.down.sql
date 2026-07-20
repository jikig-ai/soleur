-- 121_byok_cap_trip_from_found.down.sql
-- Down-migration for #5917: restore the migration-061 body of
-- record_byok_use_and_check_cap VERBATIM (the knowingly-prior committed
-- source state — trip decided by the `v_paused_at IS NULL AND v_total >
-- v_cap` pre-read guard).
--
-- NOTE: this restores the REPO's prior source (mig 061), NOT the rogue
-- dev-only `byok_cap_kill_tripped_while_paused` drift that motivated #5917
-- (that body was never in the repo and must not be reintroduced).

BEGIN;

CREATE OR REPLACE FUNCTION public.record_byok_use_and_check_cap(
  p_invocation_id   uuid,
  p_founder_id      uuid,
  p_workspace_id    uuid,
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
    invocation_id, founder_id, workspace_id, agent_role, token_count, unit_cost_cents
  ) VALUES (
    p_invocation_id, p_founder_id, p_workspace_id, p_agent_role, p_token_count, p_unit_cost_cents
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

REVOKE ALL ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, uuid, text, int, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, uuid, text, int, int)
  TO service_role;

COMMENT ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, uuid, text, int, int) IS
  'Atomic per-founder kill-switch: row-locks public.users, appends '
  'audit_byok_use row (with workspace_id, Phase 3 #4229), SUMs 1-hour '
  'cumulative grouped by founder_id (PR-F invariant), flips '
  'runtime_paused_at on cap breach. Service-role-only.';

COMMIT;
