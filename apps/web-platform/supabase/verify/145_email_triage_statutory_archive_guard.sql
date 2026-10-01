-- Verify 145_email_triage_statutory_archive_guard.sql (#9284).
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (run-verify.sh parses tab-separated (check_name TEXT,
-- bad INT) rows under ON_ERROR_STOP=1).
--
-- WHY THIS FILE EXISTS. The statutory pin is a regulated-surface invariant a
-- later CREATE OR REPLACE could silently drop; only the live function
-- definition observes a bad/partial apply.

-- (1) Statutory pin present in the live body.
SELECT 'statutory_pin' AS check_name,
       CASE WHEN pg_get_functiondef(
              'public.set_email_triage_status(uuid,text)'::regprocedure)
                 LIKE '%statutory rows are never archived%'
            THEN 0 ELSE 1 END AS bad;

-- (2) Workspace-OWNER authz preserved (not reverted to the 102 user_id pin).
SELECT 'workspace_owner_authz' AS check_name,
       CASE WHEN pg_get_functiondef(
              'public.set_email_triage_status(uuid,text)'::regprocedure)
                 LIKE '%is_email_triage_workspace_owner%'
            THEN 0 ELSE 1 END AS bad;

-- (3) EXECUTE still limited to authenticated.
SELECT 'grant_authenticated_only' AS check_name,
       CASE WHEN has_function_privilege(
              'authenticated',
              'public.set_email_triage_status(uuid,text)', 'EXECUTE')
            THEN 0 ELSE 1 END AS bad;
