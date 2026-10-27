-- 176_users_restrictive_policy_subqueries.sql
-- Fix for #10764 ("Red on main: tenant-integration").
--
-- The three RESTRICTIVE FOR UPDATE policies on public.users created by
-- migrations 016 (github_username), 017_kb_sync_history and
-- 017_project_health_snapshot each embed a correlated self-subquery:
--
--     <col> IS NOT DISTINCT FROM (SELECT <col> FROM public.users
--                                  WHERE id = auth.uid())
--
-- Postgres plans that uncorrelated scalar subquery as an InitPlan whose inner
-- scan is a Seq Scan over public.users, with the caller's SELECT-side RLS
-- (including a per-row is_jti_denied_from_jwt() call) evaluated per scanned row.
-- While migration 006's REVOKE left authenticated with only column-level
-- UPDATE(email), the privilege check fired first and the test suite only ever
-- saw 42501. When the table-level UPDATE grant exists on a project — prd's
-- actual posture, reproduced on dev by the grants-snapshot apply of 2026-10-26 —
-- the same denied UPDATE executes and takes ~17.5s on dev's ~295k-row users
-- table, exceeding the API role's ~8s statement_timeout and surfacing 57014
-- (query_canceled). Measured live on dev via rolled-back EXPLAIN ANALYZE under
-- SET ROLE authenticated + request.jwt.claims.
--
-- The fix replaces each self-subquery with a plpgsql STABLE SECURITY DEFINER
-- function that does a parameterized primary-key lookup of the caller's own
-- row. SECURITY DEFINER (not INVOKER) is load-bearing: an INVOKER function's
-- inner SELECT runs under the CALLER's SELECT RLS on public.users, which drags
-- the users_jti_not_denied policy's is_jti_denied_from_jwt() into a per-row
-- filter — measured to hang the inner query past the 8s statement_timeout on
-- dev. DEFINER runs the PK lookup under the owner (RLS-bypassed); the function
-- can only ever return auth.uid()'s own row, so no disclosure is added. plpgsql is load-bearing: a LANGUAGE sql function is inlinable and would
-- reproduce the same InitPlan. Semantics are preserved verbatim — each function
-- returns auth.uid()'s row value, identical to the subquery, and NULL (no
-- caller row) degrades to `col IS NULL` exactly as an empty subquery did.
-- Policy names are preserved because scripts/check-tom4-rls-posture.sh replays
-- CREATE POLICY statements keyed on policy name.
--
-- EXECUTE is granted to authenticated only: the policies evaluate under the
-- caller's role, service_role and postgres bypass RLS entirely, and anon never
-- reaches UPDATE on public.users. Under DEFINER the inner read is still pinned
-- to auth.uid()'s row, so they disclose nothing a self-SELECT would not.

CREATE OR REPLACE FUNCTION public.users_own_github_username()
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v text;
BEGIN
  SELECT github_username INTO v FROM public.users WHERE id = auth.uid();
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.users_own_kb_sync_history()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v jsonb;
BEGIN
  SELECT kb_sync_history INTO v FROM public.users WHERE id = auth.uid();
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.users_own_health_snapshot()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v jsonb;
BEGIN
  SELECT health_snapshot INTO v FROM public.users WHERE id = auth.uid();
  RETURN v;
END;
$$;

-- Supabase's default privileges hand EXECUTE to anon/authenticated/service_role
-- explicitly (not via PUBLIC), so PUBLIC alone does not strip them — revoke the
-- API roles by name, then re-grant only authenticated (the sole role these
-- policies evaluate under; service_role and postgres bypass RLS, anon never
-- reaches UPDATE on public.users).
REVOKE ALL ON FUNCTION public.users_own_github_username() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.users_own_kb_sync_history() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.users_own_health_snapshot() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.users_own_github_username() TO authenticated;
GRANT EXECUTE ON FUNCTION public.users_own_kb_sync_history() TO authenticated;
GRANT EXECUTE ON FUNCTION public.users_own_health_snapshot() TO authenticated;

-- Recreate the three policies verbatim except for the subquery -> function
-- swap. USING/WITH CHECK shapes and the TO clause (present only on
-- health_snapshot) are preserved byte-for-byte in intent.

DROP POLICY IF EXISTS "Users cannot update github_username directly" ON public.users;
CREATE POLICY "Users cannot update github_username directly"
  ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  USING (true)
  WITH CHECK (
    github_username IS NOT DISTINCT FROM public.users_own_github_username()
  );

DROP POLICY IF EXISTS "Users cannot update kb_sync_history directly" ON public.users;
CREATE POLICY "Users cannot update kb_sync_history directly"
  ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  USING (true)
  WITH CHECK (
    kb_sync_history IS NOT DISTINCT FROM public.users_own_kb_sync_history()
  );

DROP POLICY IF EXISTS "Prevent client health_snapshot update" ON public.users;
CREATE POLICY "Prevent client health_snapshot update" ON public.users
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (
    health_snapshot IS NOT DISTINCT FROM public.users_own_health_snapshot()
  );
