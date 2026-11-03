-- verify/183_egress_audit_window_summary.sql
-- Runtime catalog sentinel for get_egress_audit_window_summary (#11238). The migration-shape
-- test asserts the SQL TEXT; this asserts the LIVE catalog after apply. Each row returns
-- bad=1 on a drift; run-verify.sh fails the deploy if any bad=1 (precedent: verify/177).
--
-- Scoped to the exact four-argument signature. The to_regprocedure(...) rows report bad = 1 for a
-- missing function (NULL, not a raised cast). The has_function_privilege rows with a literal signature
-- raise instead of reporting if the function is missing; either way run-verify.sh fails the deploy. The 177 function and the two rollup table
-- rows are asserted in verify/177 and are not repeated here. Supabase default privileges
-- re-grant EXECUTE to anon and service_role, so every non-authenticated role is checked by name.
-- A NULL proacl means the default ACL, i.e. PUBLIC holds EXECUTE; aclexplode(NULL) yields no rows, so the
-- PUBLIC row also tests proacl IS NULL, and the grantee-set row uses IS DISTINCT FROM (a NOT IN list with a
-- NULL member would pass vacuously). The window row proves the live body carries the window check.

SELECT 'egress_window_summary_is_definer' AS check_name,
       CASE WHEN COALESCE((SELECT p.prosecdef FROM pg_proc p
                            WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)')), false)
            THEN 0 ELSE 1 END::int AS bad
UNION ALL
SELECT 'egress_window_summary_is_stable',
       CASE WHEN COALESCE((SELECT p.provolatile = 's' FROM pg_proc p
                            WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)')), false)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'egress_window_summary_search_path_pinned',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c
                          WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)')
                            AND c LIKE 'search_path=%pg_temp%')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'egress_window_summary_plan_cache_mode_custom',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c
                          WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)')
                            AND c = 'plan_cache_mode=force_custom_plan')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'egress_window_summary_checks_jti_denylist',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p
                          WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)')
                            AND p.prosrc LIKE '%is_jti_denied_from_jwt()%')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'egress_window_summary_validates_window',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p
                          WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)')
                            AND p.prosrc LIKE '%egress audit: invalid window%'
                            AND p.prosrc LIKE '%CASE p_window%')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'egress_window_summary_anon_revoked',
       CASE WHEN has_function_privilege('anon',
              'public.get_egress_audit_window_summary(uuid, integer, text, text)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'egress_window_summary_service_role_revoked',
       CASE WHEN has_function_privilege('service_role',
              'public.get_egress_audit_window_summary(uuid, integer, text, text)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'egress_window_summary_public_revoked',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
               WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)')
                 AND a.grantee = 0 AND a.privilege_type = 'EXECUTE')
              OR EXISTS (SELECT 1 FROM pg_proc p
                          WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)') AND p.proacl IS NULL)
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'egress_window_summary_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated',
              'public.get_egress_audit_window_summary(uuid, integer, text, text)', 'EXECUTE')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'egress_window_summary_grantee_set_is_only_authenticated',
       CASE WHEN (SELECT count(*) FROM pg_proc p, aclexplode(p.proacl) a
                   WHERE p.oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)')
                     AND a.privilege_type = 'EXECUTE'
                     AND a.grantee IS DISTINCT FROM (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
                     AND a.grantee IS DISTINCT FROM (SELECT proowner FROM pg_proc WHERE oid = to_regprocedure('public.get_egress_audit_window_summary(uuid, integer, text, text)'))
                ) = 0 THEN 0 ELSE 1 END::int;
