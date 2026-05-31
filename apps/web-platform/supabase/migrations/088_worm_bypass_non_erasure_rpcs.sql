-- 088_worm_bypass_non_erasure_rpcs.sql
-- GDPR — privilege-free WORM bypass for the two NON-erasure RPCs. Issue #4702.
--
-- PROBLEM (broken in production): migration 087 (#4696) converted the entire
-- account-delete (Art. 17 erasure) saga off the superuser-only
--   SET LOCAL session_replication_role = 'replica';
-- WORM bypass onto the privilege-free custom GUC `app.worm_bypass`. That GUC is
-- superuser-only (PGC_SUSET); the SECURITY DEFINER RPCs are owned by `postgres`,
-- which on managed Supabase is NOT a superuser, so the SET raises
-- `42501 permission denied to set parameter "session_replication_role"` BEFORE
-- the DML. 087 deliberately scoped itself to the erasure path and deferred the
-- two NON-erasure RPCs that carry the identical broken bypass to #4702
-- (087.sql lines 57-59):
--
--   * purge_workspace_member_actions()        — the pg_cron 7-year retention
--     DELETE sweep (defined mig 063). The 42501 raises before the DELETE, so the
--     sweep is silently a permanent no-op → workspace_member_actions audit PII
--     accumulates past its lawful 7-year window (Art. 5(1)(e) storage-limitation
--     drift).
--   * revoke_template_authorization(text, text) — the founder/auto-revoke UPDATE
--     (defined mig 053). The 42501 raises on every call that reaches the bypass,
--     for both the founder-initiated revoke (/api/template-authorizations/revoke)
--     and the service-role auto-revoke side effect (is-template-authorized.ts,
--     reasons 'expired'/'quota_exhausted'). Founders cannot withdraw a template
--     authorization (Art. 7(3) "as easily withdrawable as given").
--
-- WHY NO TRIGGER EDITS: migration 087 §1.2/§1.5 already rewrote the trigger
-- functions `template_authorizations_no_mutate()` and
-- `workspace_member_actions_no_mutate()` to honor
--   current_setting('app.worm_bypass', true) = 'on'
-- and the triggers EXECUTE FUNCTION those same functions (mig 063 L133/L139,
-- mig 053 L181/L187). So ONLY the two RPC bodies need the bypass-GUC swap.
-- 088 is RPC-body-only — re-CREATEing the trigger functions here would be
-- needless drift the 087 test's list↔migration reconciliation does not cover.
--
-- FIX: in each RPC body replace
--   SET LOCAL session_replication_role = 'replica';   →  SET LOCAL app.worm_bypass = 'on';
--   RESET session_replication_role;                    →  SET LOCAL app.worm_bypass = 'off';
-- (re-arm immediately after the single write). Custom namespaced GUCs require no
-- special privilege, so the 42501 is gone. Every other line of each RPC body is
-- preserved verbatim — authz checks, the 8-value reason-enum gate, the
-- founder-attribution gate, search_path, grants, RAISE LOG.
--
-- SCOPE — the two non-erasure RPCs deferred from 087, only:
--   * purge_workspace_member_actions      (mig 063) — retention DELETE
--   * revoke_template_authorization        (mig 053) — revoke UPDATE
-- NOT in scope: the trigger functions (already correct after 087), any table /
-- trigger / index / RLS / grant change, and the pg_cron schedule (already exists,
-- mig 063 — untouched here).
--
-- Conventions: idempotent (CREATE OR REPLACE), no outer BEGIN/COMMIT (Supabase
-- wraps), search_path pinned on SECURITY DEFINER functions
-- (cq-pg-security-definer-search-path-pin-pg-temp). Existing function grants are
-- preserved by CREATE OR REPLACE; re-stated below (defense-in-depth, mirrors 087).

-- =====================================================================
-- 1. purge_workspace_member_actions — pg_cron 7-year retention DELETE
-- =====================================================================
--
-- Re-CREATE verbatim from mig 063 §7 EXCEPT the two bypass lines. pg_cron
-- invokes this wrapper instead of a direct DELETE; the pure-reject WORM trigger
-- would silently block a direct DELETE (learning
-- 2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md). Observability:
-- cron.job_run_details (auto) + the RAISE LOG row → Supabase logs → Vector →
-- Better Stack.

CREATE OR REPLACE FUNCTION public.purge_workspace_member_actions()
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL app.worm_bypass = 'on';
  DELETE FROM public.workspace_member_actions
   WHERE created_at < now() - interval '7 years';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';
  RAISE LOG 'audit_retention_purge table=workspace_member_actions deleted_count=%', v_rows;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_workspace_member_actions()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_workspace_member_actions()
  TO postgres;

COMMENT ON FUNCTION public.purge_workspace_member_actions() IS
  'pg_cron-invoked 7-year retention purge. SET LOCAL app.worm_bypass=''on'' '
  'bypasses the pure-reject WORM trigger (direct DELETE from cron would silently '
  'fail — learning 2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep); '
  're-armed ''off'' after the DELETE. Privilege-free GUC (replaces the prior '
  'superuser-only replica-role bypass that raised 42501 on managed Supabase). '
  'Observability: cron.job_run_details (auto) + RAISE LOG. #4231 #4702.';

-- =====================================================================
-- 2. revoke_template_authorization — founder / auto-revoke UPDATE
-- =====================================================================
--
-- Re-CREATE verbatim from mig 053 §(f) EXCEPT the two bypass lines. Preserves the
-- authenticated-session guard, the full 8-value p_reason enum gate, and the
-- founder-attribution gate (PR-I user-impact-reviewer FINDING 1) — only the
-- bypass GUC changes.

CREATE OR REPLACE FUNCTION public.revoke_template_authorization(
  p_template_hash text,
  p_reason        text
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
  v_founder_id uuid := auth.uid();
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'revoke_template_authorization: authenticated session required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason NOT IN (
    'founder_revoked', 'quota_exhausted', 'expired', 'dsr_erasure',
    'regulator_ordered', 'vendor_tos_revoked', 'policy_violation',
    'quarantine_retroactive'
  ) THEN
    RAISE EXCEPTION 'revoke_template_authorization: invalid reason %', p_reason
      USING ERRCODE = '22023';
  END IF;

  -- Authenticated callers (founder-initiated revoke surface at
  -- /api/template-authorizations/revoke) MUST use reason='founder_revoked'.
  -- The other 7 enum values are reserved for service-role / postgres
  -- callers: 'quota_exhausted' / 'expired' fire from the
  -- isTemplateAuthorized predicate's auto-revoke side effect; 'dsr_erasure'
  -- fires from anonymise_template_authorizations; the remaining four are
  -- reserved for operator surfaces (regulator orders, vendor TOS, AUP
  -- enforcement, classifier feedback in PR-I+1). Without this gate, an
  -- authenticated founder calling supabase-js RPC directly could stamp
  -- their OWN row with any reason in the enum (RLS scopes by auth.uid()
  -- so cross-tenant is impossible, but the founder's own audit-trail
  -- attribution would break — surfaced by PR-I multi-agent review,
  -- user-impact-reviewer FINDING 1).
  IF auth.uid() IS NOT NULL AND p_reason <> 'founder_revoked' THEN
    RAISE EXCEPTION 'revoke_template_authorization: authenticated callers must use reason=founder_revoked (got %)', p_reason
      USING ERRCODE = '42501';
  END IF;

  -- WORM trigger blocks all UPDATEs including founder-initiated revoke; bypass is required.
  -- app.worm_bypass='on' makes the no-mutate trigger function skip its reject for
  -- this transaction (privilege-free GUC honored by template_authorizations_no_mutate
  -- after mig 087; was session_replication_role, superuser-only → 42501 on managed
  -- Supabase, #4702). Re-armed 'off' after the UPDATE.
  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.template_authorizations
     SET revoked_at = now(),
         revocation_reason = p_reason
   WHERE founder_id = v_founder_id
     AND template_hash = p_template_hash
     AND revoked_at IS NULL;
  GET DIAGNOSTICS affected = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';

  RETURN affected;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_template_authorization(text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_template_authorization(text, text)
  TO authenticated;

COMMENT ON FUNCTION public.revoke_template_authorization(text, text) IS
  'Founder-initiated revoke (Art. 7(3) "as easily withdrawable as given"). '
  'Also called auto-revoke-side-effect from the isTemplateAuthorized '
  'predicate on quota/expired detection so the scope-grants UI does '
  'not display lying rows. WORM bypass via SET LOCAL app.worm_bypass=''on'' '
  '(privilege-free; replaces the prior superuser-only replica-role GUC that '
  'raised 42501 on managed Supabase); re-armed ''off'' after the UPDATE. #4702.';
