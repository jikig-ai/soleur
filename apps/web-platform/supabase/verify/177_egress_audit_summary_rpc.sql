-- verify/177_egress_audit_summary_rpc.sql
-- Runtime catalog sentinel for get_egress_audit_summary (#9545 PR2). The migration-shape
-- test asserts the SQL TEXT; this asserts the LIVE catalog after apply. Each row returns
-- bad=1 on a drift; run-verify.sh fails the deploy if any bad=1 (precedent: verify/158).
--
-- The member read surface must be exactly: SECURITY DEFINER, STABLE, search_path pinned,
-- EXECUTE for `authenticated` only (Supabase default privileges re-grant to anon and
-- service_role, so every non-authenticated role is checked by name), and the rollup table
-- must stay un-readable by `authenticated` with zero policies.

SELECT 'egress_summary_is_definer' AS check_name,
       CASE WHEN p.prosecdef THEN 0 ELSE 1 END::int AS bad
  FROM pg_proc p
 WHERE p.oid = 'public.get_egress_audit_summary(uuid, integer, text)'::regprocedure
UNION ALL
SELECT 'egress_summary_is_stable',
       CASE WHEN p.provolatile = 's' THEN 0 ELSE 1 END::int
  FROM pg_proc p
 WHERE p.oid = 'public.get_egress_audit_summary(uuid, integer, text)'::regprocedure
UNION ALL
SELECT 'egress_summary_search_path_pinned',
       CASE WHEN p.proconfig IS NOT NULL
             AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c
                          WHERE c LIKE 'search_path=%pg_temp%')
            THEN 0 ELSE 1 END::int
  FROM pg_proc p
 WHERE p.oid = 'public.get_egress_audit_summary(uuid, integer, text)'::regprocedure
UNION ALL
SELECT 'egress_summary_anon_revoked',
       CASE WHEN has_function_privilege('anon',
              'public.get_egress_audit_summary(uuid, integer, text)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'egress_summary_service_role_revoked',
       CASE WHEN has_function_privilege('service_role',
              'public.get_egress_audit_summary(uuid, integer, text)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'egress_summary_public_revoked',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
               WHERE p.oid = 'public.get_egress_audit_summary(uuid, integer, text)'::regprocedure
                 AND a.grantee = 0 AND a.privilege_type = 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'egress_summary_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated',
              'public.get_egress_audit_summary(uuid, integer, text)', 'EXECUTE')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'egress_summary_grantee_set_is_only_authenticated',
       CASE WHEN (SELECT count(*) FROM pg_proc p, aclexplode(p.proacl) a
                   WHERE p.oid = 'public.get_egress_audit_summary(uuid, integer, text)'::regprocedure
                     AND a.privilege_type = 'EXECUTE'
                     AND a.grantee NOT IN (
                           (SELECT oid FROM pg_roles WHERE rolname = 'authenticated'),
                           (SELECT proowner FROM pg_proc
                             WHERE oid = 'public.get_egress_audit_summary(uuid, integer, text)'::regprocedure))
                ) = 0 THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'egress_rollup_authenticated_select_revoked',
       CASE WHEN has_table_privilege('authenticated',
              'public.workspace_egress_audit_rollup', 'SELECT')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'egress_rollup_has_no_policy',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policies
                          WHERE schemaname = 'public'
                            AND tablename = 'workspace_egress_audit_rollup')
            THEN 1 ELSE 0 END::int;
