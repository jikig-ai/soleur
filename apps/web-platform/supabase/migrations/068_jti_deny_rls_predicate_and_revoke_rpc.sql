-- 068_jti_deny_rls_predicate_and_revoke_rpc.sql
-- feat-one-shot-jti-revoke-rls-3930-3932 — closes the cross-process JWT-
-- deny gap PR-E (#3922) left open. Bundles two deferred-scope-outs:
--
--   #3930 — admin `revoke_jti(p_jti, p_founder_id, p_reason)` RPC +
--           founder-readable `my_revocation_status()` reader.
--   #3932 — PostgREST-side RLS predicate so a stolen JWT used DIRECTLY
--           against PostgREST (outside the Node `getFreshTenantClient`
--           boundary) cannot read/write tenant tables after its jti
--           lands in `public.denied_jti`.
--
-- Surfaces (3 functions + 21 RESTRICTIVE policies + 1 GRANT):
--   (A) public.revoke_jti(uuid, uuid, text)        — service-role-only writer.
--   (B) public.my_revocation_status()              — authenticated reader.
--   (C) public.is_jti_denied_from_jwt()            — STABLE helper used by RLS.
--   (D) <table>_jti_not_denied RESTRICTIVE policies on 21 tenant tables.
--   (E) GRANT EXECUTE ON public.is_jti_denied(uuid) TO authenticated
--       (the wrapped reader from mig 037; required because the new helper
--        SECURITY DEFINERs into it).
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(c) record-keeping AND Art. 32(1)(b)
-- "ongoing confidentiality" — extends PR-E's in-Node deny to cross-
-- process (PostgREST). No new Article 30 PA: PA1 (Account & Auth) already
-- covers `denied_jti`; jti is a random UUID (not personal data);
-- founder_id is already in PA1 scope.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER function pins `SET search_path = public, pg_temp` (public first)
-- and qualifies every relation as public.<table>.
--
-- NOVEL PATTERN CALLOUT: this is the FIRST RLS predicate in the codebase
-- that reads `current_setting('request.jwt.claims', true)::jsonb->>'jti'`.
-- Verified via `grep -rn "request\.jwt\.claims" apps/web-platform/supabase/migrations/*.sql`
-- → zero matches at HEAD. The `true` arg to current_setting returns NULL
-- on unset GUC (service-role context); ->>'jti' on NULL returns NULL;
-- (NULL)::uuid → NULL; `EXISTS (WHERE jti = NULL)` → false. The outer
-- `NOT public.is_jti_denied_from_jwt()` then returns true (access granted),
-- matching the existing fail-open PR-E semantics for service-role.
--
-- RESTRICTIVE-policy combination semantics: Postgres AND-combines all
-- RESTRICTIVE policies AND OR-combines all PERMISSIVE policies. The new
-- `<table>_jti_not_denied` RESTRICTIVE policy stacks on top of every
-- existing PERMISSIVE policy (mig 059 workspace-keyed + legacy
-- auth.uid()=user_id where still present). Belt-and-suspenders: both
-- USING and WITH CHECK include the same predicate so SELECT/INSERT/
-- UPDATE/DELETE all gate on the same expression.

-- =====================================================================
-- 1. revoke_jti — service-role-only writer for public.denied_jti
-- =====================================================================
-- Body is a single INSERT into the WORM table. The denied_jti row IS the
-- audit artifact per Article 30 PA1 §(g)(10) "audit logging via Supabase
-- + pino"; operator-side `apps/web-platform/scripts/revoke-jti.ts` post-
-- call re-reads the row for founder_id-mismatch sanity.

CREATE OR REPLACE FUNCTION public.revoke_jti(
  p_jti        uuid,
  p_founder_id uuid,
  p_reason     text
) RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  -- ON CONFLICT DO NOTHING — operator may double-revoke the same jti
  -- (typo-retry, drift between two operators). 23505 unique_violation
  -- would surface as a confusing CLI error instead of a no-op. The
  -- denied_jti table's PK is `jti`, so duplicate inserts hit the same
  -- conflict target deterministically.
  INSERT INTO public.denied_jti (jti, founder_id, denied_at, reason)
  VALUES (p_jti, p_founder_id, now(), p_reason)
  ON CONFLICT (jti) DO NOTHING;
$$;

-- Explicit revoke from anon + authenticated is load-bearing per the
-- comment in mig 037: Supabase's default privileges auto-GRANT EXECUTE
-- to all three roles; named-role REVOKE is required. service_role is
-- granted explicitly so the operator CLI (which uses createServiceClient)
-- can call.
REVOKE ALL ON FUNCTION public.revoke_jti(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_jti(uuid, uuid, text) TO service_role;

COMMENT ON FUNCTION public.revoke_jti(uuid, uuid, text) IS
  'Admin revoke writer for public.denied_jti. SECURITY DEFINER, service-role-only. '
  'Operator invocation via apps/web-platform/scripts/revoke-jti.ts. PR #3930.';

-- =====================================================================
-- 2. my_revocation_status — founder-readable status (jti NOT exposed)
-- =====================================================================
-- Mirrors `check_my_revocation` from mig 067 (workspace-removal sibling):
-- 28000 raise on NULL auth.uid(); single LIMIT 1 SELECT of latest denied
-- row for the caller's founder_id; fallthrough to (false, NULL, NULL).
-- DOES NOT return jti (jti enumeration side-channel mitigation per #3930).

CREATE OR REPLACE FUNCTION public.my_revocation_status()
  RETURNS TABLE(revoked boolean, denied_at timestamptz, reason text)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- Defense-in-depth: under SECURITY DEFINER context, a forged caller
  -- with NULL auth.uid() (or service-role context) would otherwise
  -- silently fall-open returning revoked=false. Fail explicit per the
  -- mig 067 check_my_revocation precedent.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  RETURN QUERY
    SELECT true, dj.denied_at, dj.reason
      FROM public.denied_jti dj
     WHERE dj.founder_id = auth.uid()
     ORDER BY dj.denied_at DESC
     LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::timestamptz, NULL::text;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.my_revocation_status()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.my_revocation_status() TO authenticated;

COMMENT ON FUNCTION public.my_revocation_status() IS
  'Founder-readable revocation status. Returns (revoked, denied_at, reason) '
  'for auth.uid()''s latest denied_jti row, or (false, NULL, NULL) if none. '
  'jti deliberately omitted per #3930 jti-enumeration side-channel mitigation.';

-- =====================================================================
-- 3. is_jti_denied_from_jwt — STABLE helper invoked by RLS predicate
-- =====================================================================
-- Wraps the mig 037 reader for the RLS-policy invocation path. Reads the
-- caller's jti from `request.jwt.claims` (set by PostgREST on every
-- authenticated request); the `true` arg to current_setting returns NULL
-- on unset GUC so service-role contexts (where the GUC is unset) safely
-- short-circuit to "not denied" → policy permits. STABLE marker lets
-- Postgres memoize within a single statement, so a 1000-row SELECT
-- triggers exactly one deny-probe — not 1000.

CREATE OR REPLACE FUNCTION public.is_jti_denied_from_jwt()
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  STABLE
  SET search_path = public, pg_temp
AS $$
  SELECT public.is_jti_denied(
    (current_setting('request.jwt.claims', true)::jsonb->>'jti')::uuid
  );
$$;

REVOKE ALL ON FUNCTION public.is_jti_denied_from_jwt()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_jti_denied_from_jwt() TO authenticated;

COMMENT ON FUNCTION public.is_jti_denied_from_jwt() IS
  'RLS-policy helper: returns true if the calling JWT''s jti is on the '
  'denied list. SECURITY DEFINER (wraps service-role-only is_jti_denied), '
  'STABLE so Postgres memoizes per-statement. PR #3932.';

-- =====================================================================
-- 4. GRANT EXECUTE on the wrapped reader to authenticated
-- =====================================================================
-- The RLS predicate `NOT public.is_jti_denied_from_jwt()` is evaluated
-- in the AUTHENTICATED role's context BEFORE the SECURITY DEFINER body
-- enters its definer scope. Postgres performs the outer-call EXECUTE
-- check on `is_jti_denied_from_jwt()` (and on `is_jti_denied(uuid)` if
-- the wrapper ever direct-calls it transitively in a non-DEFINER path)
-- against the AUTHENTICATED role. Without this GRANT, every PostgREST
-- query under authenticated returns "42501 permission denied for
-- function is_jti_denied" instead of evaluating the policy. See
-- learning 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md.
--
-- ACKNOWLEDGED SECURITY NOTE — JTI-ORACLE ENUMERATION SURFACE:
-- An authenticated caller could invoke `is_jti_denied('<arbitrary-uuid>')`
-- directly via PostgREST and receive a boolean. This is acknowledged
-- as acceptable: (i) the function returns ONLY a boolean (never the
-- row); (ii) `jti` is a random UUID with 2^128 unguessable search
-- space, making practical enumeration of the deny list infeasible
-- without first stealing a JWT; (iii) the `denied_jti` table itself
-- has ZERO RLS policies and is service-role-only per mig 037, so the
-- row contents (founder_id, denied_at, reason) remain hidden. Three
-- review agents flagged this surface; security-sentinel's argument
-- (UUID space + boolean-only return) carried. If the boolean leak ever
-- becomes load-bearing for a future attack, the mitigation is to drop
-- the GRANT on `is_jti_denied(uuid)` and refactor the wrapper to
-- inline the EXISTS check under a stricter DEFINER body that does NOT
-- accept an arbitrary uuid argument.

GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO authenticated;

-- =====================================================================
-- 5. RESTRICTIVE policies — one per tenant table (21 total)
-- =====================================================================
-- The 21 tenant tables holding authenticated-reachable policies.
-- Derived empirically (grep CREATE POLICY + FOR ... TO authenticated +
-- legacy `FOR ALL`/`FOR INSERT` without explicit role which defaults to
-- PUBLIC). Excluded: the 9 service-role-only tables (denied_jti,
-- mint_rate_window, processed_stripe_events, _schema_migrations,
-- processed_github_events, runtime_mint_intent, dsar_export_audit_pii,
-- tc_acceptances, tenant_deploy_audit) which have zero authenticated
-- policies by design.
-- Note: the previous 19-table list (pre-review) MISSED `organizations`
-- (mig 053:159) and `workspace_member_removals` (mig 062:128) — both
-- carry `TO authenticated` PERMISSIVE policies, so the RESTRICTIVE
-- jti-deny predicate would silently NOT apply there without inclusion.
-- Added back in this fix; verify-068 count assertion bumped to 21.
--
-- Each policy:
--   - AS RESTRICTIVE — AND-combined with existing PERMISSIVE policies.
--   - FOR ALL TO authenticated — covers SELECT/INSERT/UPDATE/DELETE.
--   - USING + WITH CHECK both pin the same predicate (belt-and-suspenders).
--   - Idempotent via DROP POLICY IF EXISTS + CREATE POLICY.
--
-- DRY via DO $$ LOOP $$ — the policy body is identical across 19 tables;
-- inlining 19 CREATE POLICY statements bloats the diff and fragments
-- review focus.

DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'conversations',
    'messages',
    'users',
    'api_keys',
    'audit_byok_use',
    'scope_grants',
    'audit_github_token_use',
    'kb_share_links',
    'push_subscriptions',
    'user_concurrency_slots',
    'dsar_export_jobs',
    'action_sends',
    'template_authorizations',
    'byok_delegations',
    'workspaces',
    'workspace_members',
    'workspace_member_attestations',
    'user_session_state',
    'message_attachments',
    'organizations',
    'workspace_member_removals'
  ];
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I_jti_not_denied ON public.%I',
      t, t
    );
    EXECUTE format(
      'CREATE POLICY %I_jti_not_denied ON public.%I '
      'AS RESTRICTIVE FOR ALL TO authenticated '
      'USING (NOT public.is_jti_denied_from_jwt()) '
      'WITH CHECK (NOT public.is_jti_denied_from_jwt())',
      t, t
    );
  END LOOP;
END $$;
