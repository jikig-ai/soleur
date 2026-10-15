-- verify/162_workspace_egress_audit_rollup.sql
-- Runtime sentinel for the egress audit rollup (precedent: verify/158). The
-- migration-shape test asserts the GRANT/REVOKE text; this asserts the LIVE
-- state post-apply: nothing but service_role may execute the three functions,
-- the table keeps RLS on with no policy, the table comment states the
-- retention, and the daily sweep job exists. Each row returns bad=1 on drift;
-- run-verify.sh fails the deploy if any bad=1.

SELECT 'ingest_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon',
              'public.ingest_egress_audit_rollup(jsonb)', 'EXECUTE')
            THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'ingest_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated',
              'public.ingest_egress_audit_rollup(jsonb)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'ingest_service_role_granted',
       CASE WHEN has_function_privilege('service_role',
              'public.ingest_egress_audit_rollup(jsonb)', 'EXECUTE')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'purge_anon_revoked',
       CASE WHEN has_function_privilege('anon',
              'public.purge_egress_audit_rollup(interval, int)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'purge_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated',
              'public.purge_egress_audit_rollup(interval, int)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'purge_service_role_granted',
       CASE WHEN has_function_privilege('service_role',
              'public.purge_egress_audit_rollup(interval, int)', 'EXECUTE')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'erase_anon_revoked',
       CASE WHEN has_function_privilege('anon',
              'public.erase_egress_audit_rollup(uuid)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'erase_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated',
              'public.erase_egress_audit_rollup(uuid)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'erase_service_role_granted',
       CASE WHEN has_function_privilege('service_role',
              'public.erase_egress_audit_rollup(uuid)', 'EXECUTE')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'table_rls_enabled',
       CASE WHEN (SELECT c.relrowsecurity FROM pg_class c
                   WHERE c.oid = 'public.workspace_egress_audit_rollup'::regclass)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'table_has_no_policy',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policy p
                          WHERE p.polrelid = 'public.workspace_egress_audit_rollup'::regclass)
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'table_anon_authenticated_no_select',
       CASE WHEN has_table_privilege('anon', 'public.workspace_egress_audit_rollup', 'SELECT')
              OR has_table_privilege('authenticated', 'public.workspace_egress_audit_rollup', 'SELECT')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'table_comment_states_retention',
       CASE WHEN obj_description('public.workspace_egress_audit_rollup'::regclass, 'pg_class')
                 LIKE '%30 days%'
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'retention_job_scheduled',
       CASE WHEN EXISTS (SELECT 1 FROM cron.job
                          WHERE jobname = 'egress-audit-rollup-retention'
                            AND command LIKE '%purge_egress_audit_rollup%')
            THEN 0 ELSE 1 END::int;
