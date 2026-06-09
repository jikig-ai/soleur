-- verify/101_workspace_debug_mode.sql
-- Runtime grant-hygiene sentinel for the debug-mode RPCs (precedent:
-- verify/097, verify/092). The migration-shape test asserts the GRANT/REVOKE
-- *text* exists; this sentinel asserts the *live* privilege state post-apply:
-- the dev-cohort harness-stream control surface must never be EXECUTE-able by
-- anon, and must stay EXECUTE-able by authenticated. Each row returns bad=1
-- on a drift; run-verify.sh fails the deploy if any bad=1.

SELECT 'set_debug_mode_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon',
              'public.set_workspace_debug_mode(uuid, boolean)', 'EXECUTE')
            THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'set_debug_mode_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated',
              'public.set_workspace_debug_mode(uuid, boolean)', 'EXECUTE')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_debug_mode_anon_revoked',
       CASE WHEN has_function_privilege('anon',
              'public.get_workspace_debug_mode(uuid)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'get_debug_mode_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated',
              'public.get_workspace_debug_mode(uuid)', 'EXECUTE')
            THEN 0 ELSE 1 END::int;
