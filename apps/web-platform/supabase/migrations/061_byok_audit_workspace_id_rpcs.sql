-- 057_byok_audit_workspace_id_rpcs.sql
-- feat-team-workspace-multi-user (#4229, PR #4225) — Phase 3.1.2.
--
-- Migration 055 added `audit_byok_use.workspace_id NOT NULL`. The legacy
-- 5-arg RPCs `write_byok_audit` (migration 037) and
-- `record_byok_use_and_check_cap` (migration 046) INSERT into
-- audit_byok_use WITHOUT supplying workspace_id, so any agent run after
-- 055 fails with a NOT NULL constraint violation. This migration extends
-- both RPC signatures with `p_workspace_id uuid` (6th positional arg)
-- and threads the value into the INSERT.
--
-- DEPENDENCY: migration 055 must have applied (audit_byok_use.workspace_id
-- column + NOT NULL constraint must exist; the JS caller in cost-writer.ts
-- now passes the value).
--
-- Sequencing: 055 + 057 MUST be applied in the SAME prd window — between
-- them, audit_byok_use writes from the legacy 5-arg signature would fail.
-- dev was already broken between 055 apply (2026-05-21) and 057 apply.
--
-- Approach: DROP FUNCTION + CREATE — the table is empty of new rows in
-- both dev and prd between 055 and 057 (legacy callers fail-closed), so
-- there is no rolling-deploy backwards-compat window to preserve via
-- additive overloading (per learning
-- `2026-05-12-stub-handlers-as-silent-undercount-vectors.md`: prefer
-- overloading when prod callers of v1 exist; here all v1 callers are
-- already failing under the NOT NULL constraint, so DROP is safe).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: SET search_path =
-- public, pg_temp pinned on both new functions.

BEGIN;

-- =====================================================================
-- 1. write_byok_audit — 6-arg signature with p_workspace_id.
-- =====================================================================

DROP FUNCTION IF EXISTS public.write_byok_audit(uuid, uuid, text, int, int);

CREATE OR REPLACE FUNCTION public.write_byok_audit(
  p_invocation_id   uuid,
  p_founder_id      uuid,
  p_workspace_id    uuid,
  p_agent_role      text,
  p_token_count     int,
  p_unit_cost_cents int
) RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  INSERT INTO public.audit_byok_use(
    invocation_id, founder_id, workspace_id, agent_role, token_count, unit_cost_cents
  )
  VALUES (
    p_invocation_id, p_founder_id, p_workspace_id, p_agent_role, p_token_count, p_unit_cost_cents
  );
$$;

REVOKE ALL ON FUNCTION public.write_byok_audit(uuid, uuid, uuid, text, int, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_byok_audit(uuid, uuid, uuid, text, int, int)
  TO service_role;

COMMENT ON FUNCTION public.write_byok_audit(uuid, uuid, uuid, text, int, int) IS
  'Service-role-only writer for audit_byok_use. RLS-bypass via SECURITY '
  'DEFINER. Phase 3 (#4229): threads p_workspace_id into the WORM row so '
  'workspace co-members see the turn in workspace_cost_aggregate.';

-- =====================================================================
-- 2. record_byok_use_and_check_cap — 6-arg signature with p_workspace_id.
-- =====================================================================
--
-- The atomic kill-switch RPC (per-founder cap, TOCTOU-safe via FOR UPDATE
-- on public.users). The cap enforcement stays per-founder (PR-F #3244
-- invariant — see plan §reconciliation-row-2). workspace_id is recorded
-- on the audit row only for attribution; the SUM still groups by
-- founder_id.

DROP FUNCTION IF EXISTS public.record_byok_use_and_check_cap(uuid, uuid, text, int, int);

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

  -- Flip runtime_paused_at on cap breach (idempotent: only when
  -- previously NULL — a second cap-breach does not re-stamp).
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
