-- verify/099_bash_autonomous_default_on_and_ack.sql
-- Runtime grant-hygiene sentinel for the autonomous-ack RPCs (mirrors
-- verify/097). The migration-shape test asserts the GRANT/REVOKE *text*; this
-- sentinel asserts the *live* privilege state post-apply: the consent-ack
-- authz surface must never be EXECUTE-able by anon, and must stay EXECUTE-able
-- by authenticated. Each row returns bad=1 on a drift; run-verify.sh fails the
-- deploy if any bad=1.

SELECT 'set_autonomous_ack_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon',
              'public.set_workspace_autonomous_ack(uuid)', 'EXECUTE')
            THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'set_autonomous_ack_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated',
              'public.set_workspace_autonomous_ack(uuid)', 'EXECUTE')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_autonomous_ack_anon_revoked',
       CASE WHEN has_function_privilege('anon',
              'public.get_workspace_autonomous_ack(uuid)', 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'get_autonomous_ack_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated',
              'public.get_workspace_autonomous_ack(uuid)', 'EXECUTE')
            THEN 0 ELSE 1 END::int;
