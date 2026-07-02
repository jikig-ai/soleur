-- 121_byok_cap_kill_tripped_while_paused.sql
-- feat-l5-runaway-guard PR-A (#5767) — P0-A fix: make the pause REAL at the
-- cap RPC layer.
--
-- The 061 body set kill_tripped ONLY on the NULL→set transition
-- (`v_paused_at IS NULL AND v_total > v_cap`). Consequence (arch-strategist
-- P0-A): an already-paused founder's NEXT spawn re-ran the cap-check, found
-- runtime_paused_at already stamped, took neither branch, and returned
-- kill_tripped=false — so the loop kept issuing Anthropic calls and kept
-- burning the founder's BYOK credits. The pause was cosmetic.
--
-- 121 makes kill_tripped reflect the PAUSED STATE, not just the transition:
--   * already paused (runtime_paused_at IS NOT NULL) → kill_tripped = true,
--     unconditionally, until the operator-resume clearer sets it NULL.
--   * not paused, over cap → flip runtime_paused_at + kill_tripped = true
--     (unchanged first-breach behavior).
--
-- Defense-in-depth: this is the backstop BEHIND the handler's spawn-entry
-- pause gate (agent-on-spawn-requested.ts). Even if the entry gate is ever
-- bypassed, the first turn's cap-check now re-blocks a paused founder.
--
-- Contract preserved (AC2 — set-never-clear): this RPC still NEVER writes
-- runtime_paused_at = NULL. The ONLY clearer is the operator-resume route.
--
-- Body-only CREATE OR REPLACE — signature + return type are IDENTICAL to
-- 061 (CREATE OR REPLACE cannot change a return type, and the 6-arg
-- signature must survive for rolling-deploy callers). No DROP FUNCTION.

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
  -- RV1 (Kieran P1.1): serialize concurrent callers on the same founder
  -- row BEFORE the prior-hour SUM. Without this lock, two concurrent
  -- calls at cap-boundary both pass the predicate (snapshot isolation
  -- reads each one's pre-INSERT state).
  SELECT runtime_cost_cap_cents, runtime_paused_at
    INTO v_cap, v_paused_at
    FROM public.users
   WHERE id = p_founder_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'record_byok_use_and_check_cap: founder % not found', p_founder_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Append the audit row first (accounting is sacred — even on
  -- already-paused tenants we record the call so cost-attribution
  -- stays accurate). Phase 3: workspace_id is now NOT NULL post-055.
  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, workspace_id, agent_role, token_count, unit_cost_cents
  ) VALUES (
    p_invocation_id, p_founder_id, p_workspace_id, p_agent_role, p_token_count, p_unit_cost_cents
  );

  -- Sum prior-hour cents AFTER the INSERT. The lock above ensures no
  -- concurrent INSERT can race between this SUM and the UPDATE below.
  -- The SUM stays grouped by founder_id (per-founder cap enforcement,
  -- PR-F invariant). workspace-grain rollups live in
  -- public.workspace_cost_aggregate (migration 055).
  SELECT COALESCE(SUM(token_count * unit_cost_cents), 0)::int
    INTO v_total
    FROM public.audit_byok_use
   WHERE founder_id = p_founder_id
     AND ts > now() - interval '1 hour';

  -- P0-A fix: kill_tripped tracks the PAUSED STATE, not just the
  -- NULL→set transition.
  --   * already paused → block unconditionally. The pause persists until
  --     the operator-resume clearer sets runtime_paused_at = NULL (the
  --     ONLY clearer). This RPC never clears it (set-never-clear, AC2).
  --   * not paused, over cap → flip runtime_paused_at (idempotent: only
  --     when previously NULL) — unchanged first-breach behavior.
  IF v_paused_at IS NOT NULL THEN
    v_tripped := true;
  ELSIF v_total > v_cap THEN
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
  'cumulative grouped by founder_id (PR-F invariant). PR-A (#5767): '
  'kill_tripped now reflects the PAUSED STATE (true whenever '
  'runtime_paused_at IS NOT NULL), not just the NULL->set transition, so a '
  'paused founder re-blocks. Never clears the pause (set-never-clear). '
  'Service-role-only.';
