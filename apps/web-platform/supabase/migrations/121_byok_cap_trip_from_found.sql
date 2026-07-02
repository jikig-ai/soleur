-- 121_byok_cap_trip_from_found.sql
-- fix(ci): byok cap-boundary FOR UPDATE double-trip (#5917).
--
-- ROOT CAUSE (H1 — dev-DB RPC drift, confirmed via pg_get_functiondef on
-- soleur-dev 2026-07-02): a migration `byok_cap_kill_tripped_while_paused`
-- (supabase ledger version 20260702195538, applied ~19:55 UTC — between the
-- last-green 19:43 and first-red 20:26 tenant-integration runs) was applied
-- directly to dev and is NOT in this repo. It rewrote the trip block to:
--
--     IF v_paused_at IS NOT NULL THEN
--       v_tripped := true;              -- reports a trip on EVERY already-paused call
--     ELSIF v_total > v_cap THEN
--       UPDATE ... ; v_tripped := true;
--     END IF;
--
-- Under the atomicity test (byok-kill-switch.atomicity.tenant-isolation),
-- the cumulative-700 caller acquires the FOR UPDATE lock AFTER the
-- cumulative-600 caller stamps runtime_paused_at, re-reads v_paused_at as
-- non-NULL, and this drifted body reports kill_tripped=true a SECOND time.
-- The test's Invariant C ("exactly one trip, on the CAP+COST crossing call")
-- correctly rejects the double-trip → `tenant-integration-required` red.
--
-- THE FIX (authoritative under BOTH the drift branch AND a hypothetical
-- genuine trip-signal fragility): derive the trip signal from the guarded
-- UPDATE's ACTUAL row-change (`FOUND`), not from a pre-read snapshot of
-- v_paused_at. The `WHERE ... AND runtime_paused_at IS NULL` predicate is
-- evaluated atomically against the current row under the FOR UPDATE lock, so
-- only ONE concurrent caller can flip NULL → non-NULL; every other caller's
-- WHERE fails to match and `FOUND` is false. This yields exactly one trip and
-- is a STRICT improvement over migration 061's `v_paused_at IS NULL AND
-- v_total > v_cap` guard (which relied on the pre-read snapshot).
--
-- Applying this migration to dev is an idempotent CREATE OR REPLACE that
-- reconciles the rogue drift AND installs the hardened body. FOR UPDATE is
-- RETAINED (it still serializes the audit INSERT↔SUM against the TOCTOU race
-- that Invariant B guards). Fail-safe property is preserved: the switch still
-- trips on cap breach.
--
-- Signature, SECURITY DEFINER, search_path pin, and grants are re-issued
-- verbatim from migration 061 (cq-pg-security-definer-search-path-pin-pg-temp).
-- No CREATE INDEX CONCURRENTLY (Supabase wraps each migration in a
-- transaction; cq-supabase-migration-no-concurrently).

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
  -- stays accurate). Phase 3 (#4229): workspace_id is NOT NULL post-055.
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

  -- Flip runtime_paused_at on cap breach. The trip signal is derived from
  -- the guarded UPDATE's ACTUAL effect (FOUND), not from the pre-read
  -- v_paused_at snapshot. The `runtime_paused_at IS NULL` predicate is
  -- evaluated atomically against the current row under the FOR UPDATE lock,
  -- so exactly one concurrent caller flips NULL → non-NULL and sees
  -- FOUND = true; every other over-cap caller's WHERE fails to match and
  -- FOUND is false. Result: exactly one trip (#5917). Idempotent: a second
  -- cap-breach does not re-stamp.
  IF v_total > v_cap THEN
    UPDATE public.users
       SET runtime_paused_at = now()
     WHERE id = p_founder_id
       AND runtime_paused_at IS NULL;
    v_tripped := FOUND;
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
  'runtime_paused_at on cap breach. Trip signal derived from the guarded '
  'UPDATE''s FOUND (#5917) → exactly one trip under concurrency. '
  'Service-role-only.';

COMMIT;
