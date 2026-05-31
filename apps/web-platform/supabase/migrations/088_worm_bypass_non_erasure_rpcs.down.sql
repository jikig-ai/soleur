-- 088_worm_bypass_non_erasure_rpcs.down.sql
-- Rollback of 088 — restores the pre-088 RPC bodies (the
-- session_replication_role WORM bypass) for purge_workspace_member_actions and
-- revoke_template_authorization.
--
-- WARNING — FORWARD-ONLY REALITY: this down migration REINSTATES the
-- prod-broken behavior. `SET LOCAL session_replication_role = 'replica'` is
-- superuser-only and raises `42501 permission denied to set parameter` on
-- managed Supabase (the postgres role owning these SECURITY DEFINER functions is
-- NOT a superuser). After this down runs on a managed project, the 7-year
-- retention purge silently no-ops again (Art. 5(1)(e) drift) and template-
-- authorization revoke 500s again (Art. 7(3)). This file exists for LOCAL
-- rollback symmetry only — it is NOT a production remediation. 088 touches only
-- these two function bodies, so there is no table/trigger/grant DDL to revert;
-- the trigger functions converted by 087 are left untouched (they still honor
-- app.worm_bypass, which the restored RPC bodies simply no longer set).

-- =====================================================================
-- 1. purge_workspace_member_actions — restore mig 063 §7 body
-- =====================================================================

CREATE OR REPLACE FUNCTION public.purge_workspace_member_actions()
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL session_replication_role = 'replica';
  DELETE FROM public.workspace_member_actions
   WHERE created_at < now() - interval '7 years';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RESET session_replication_role;
  RAISE LOG 'audit_retention_purge table=workspace_member_actions deleted_count=%', v_rows;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_workspace_member_actions()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_workspace_member_actions()
  TO postgres;

COMMENT ON FUNCTION public.purge_workspace_member_actions() IS
  'pg_cron-invoked 7-year retention purge. SET LOCAL session_replication_role='
  '''replica'' bypasses the pure-reject WORM trigger (direct DELETE from cron '
  'would silently fail — learning 2026-05-15-worm-trigger-blocks-pg-cron-'
  'retention-sweep). Observability: cron.job_run_details (auto) + RAISE LOG. #4231.';

-- =====================================================================
-- 2. revoke_template_authorization — restore mig 053 §(f) body
-- =====================================================================

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

  IF auth.uid() IS NOT NULL AND p_reason <> 'founder_revoked' THEN
    RAISE EXCEPTION 'revoke_template_authorization: authenticated callers must use reason=founder_revoked (got %)', p_reason
      USING ERRCODE = '42501';
  END IF;

  -- WORM trigger blocks all UPDATEs including founder-initiated revoke; bypass is required.
  -- session_replication_role='replica' makes Postgres skip BEFORE
  -- triggers in this transaction. RESET below.
  SET LOCAL session_replication_role = 'replica';
  UPDATE public.template_authorizations
     SET revoked_at = now(),
         revocation_reason = p_reason
   WHERE founder_id = v_founder_id
     AND template_hash = p_template_hash
     AND revoked_at IS NULL;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET session_replication_role;

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
  'not display lying rows.';
