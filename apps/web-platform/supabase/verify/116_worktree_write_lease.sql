-- Verify 116_worktree_write_lease.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations. Asserts post-apply state from migration 116:
--   * worktree_write_lease exists with RLS enabled.
--   * exactly one PERMISSIVE SELECT policy (worktree_write_lease_member_select);
--     zero write policies.
--   * acquire/touch/release RPCs exist + SECURITY DEFINER + the exact named-arg
--     signatures the supabase-js client sends (proargnames parity).
--   * none of the three RPCs is EXECUTE-able by anon or authenticated;
--     service_role retains EXECUTE (writes via service_role RPCs only).
--   * the FUNCTION EXECUTE grants are the write-access control surface; the
--     TABLE itself keeps authenticated's default SELECT grant (the member SELECT
--     policy needs it to be reachable), with row access gated by RLS — anon has
--     no policy ⇒ no rows. This migration does NOT revoke table grants (029
--     RLS-only pattern); the function-revoke matrix above is the access gate.

-- (1) table exists + RLS enabled
SELECT 'worktree_write_lease_rls_enabled' AS check_name,
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int AS bad
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname = 'worktree_write_lease'
   AND c.relrowsecurity = true
UNION ALL
-- (2) exactly one PERMISSIVE SELECT policy
SELECT 'worktree_write_lease_one_select_policy',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'worktree_write_lease'
   AND policyname = 'worktree_write_lease_member_select'
   AND cmd = 'SELECT' AND permissive = 'PERMISSIVE'
UNION ALL
-- (3) zero non-SELECT (write) policies
SELECT 'worktree_write_lease_no_write_policies',
       CASE WHEN count(*) = 0 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'worktree_write_lease'
   AND cmd <> 'SELECT'
UNION ALL
-- (4) acquire present + SECURITY DEFINER
SELECT 'acquire_worktree_lease_fn_secdef',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'acquire_worktree_lease'
   AND p.prosecdef = true
UNION ALL
-- (5) touch present + SECURITY DEFINER
SELECT 'touch_worktree_lease_fn_secdef',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'touch_worktree_lease'
   AND p.prosecdef = true
UNION ALL
-- (6) release present + SECURITY DEFINER
SELECT 'release_worktree_lease_fn_secdef',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'release_worktree_lease'
   AND p.prosecdef = true
UNION ALL
-- (7-12) RPC EXECUTE revoke matrix: anon + authenticated must NOT execute.
SELECT 'acquire_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.acquire_worktree_lease(uuid, text, text)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'acquire_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.acquire_worktree_lease(uuid, text, text)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'touch_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.touch_worktree_lease(uuid, text, text, bigint)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'touch_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.touch_worktree_lease(uuid, text, text, bigint)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'release_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.release_worktree_lease(uuid, text, text, bigint)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'release_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.release_worktree_lease(uuid, text, text, bigint)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
-- (13-15) service_role retains EXECUTE on all three.
SELECT 'acquire_service_role_grant',
       CASE WHEN has_function_privilege('service_role', 'public.acquire_worktree_lease(uuid, text, text)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'touch_service_role_grant',
       CASE WHEN has_function_privilege('service_role', 'public.touch_worktree_lease(uuid, text, text, bigint)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'release_service_role_grant',
       CASE WHEN has_function_privilege('service_role', 'public.release_worktree_lease(uuid, text, text, bigint)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
-- (16-18) Named-arg parity: a supabase-js .rpc() call routes by ARG NAME, so a
-- drift between the migration's parameter names and the TS client's literals is
-- a runtime PGRST/404, which the typed-signature checks above do NOT catch.
-- Assert proargnames CONTAINS the exact input names the client sends
-- (server/worktree-write-lease.ts). `@>` (array-contains) ignores acquire's
-- RETURNS TABLE OUT columns (host_id, lease_generation), so it pins only the
-- input arg names.
SELECT 'acquire_argnames',
       CASE WHEN p.proargnames @> ARRAY['p_workspace_id','p_worktree_id','p_host_id']
            THEN 0 ELSE 1 END::int
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'acquire_worktree_lease'
UNION ALL
SELECT 'touch_argnames',
       CASE WHEN p.proargnames @> ARRAY['p_workspace_id','p_worktree_id','p_host_id','p_lease_generation']
            THEN 0 ELSE 1 END::int
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'touch_worktree_lease'
UNION ALL
SELECT 'release_argnames',
       CASE WHEN p.proargnames @> ARRAY['p_workspace_id','p_worktree_id','p_host_id','p_lease_generation']
            THEN 0 ELSE 1 END::int
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'release_worktree_lease';

-- NOTE: no table-grant assertions — this migration mirrors 029's RLS-only
-- pattern (RLS + SELECT-only policy gates reads; absence of write policies
-- gates writes). authenticated retains its default table grants (the policy
-- needs the SELECT grant to be reachable); anon rows are denied by RLS, not by
-- a table-grant revoke. The function-level revoke matrix above is the access
-- control surface for the write path.
