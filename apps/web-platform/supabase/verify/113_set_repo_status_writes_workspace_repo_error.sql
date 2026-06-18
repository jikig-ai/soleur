-- Verify 113_set_repo_status_writes_workspace_repo_error.sql.
--
-- Contract: every row returns `check_name` + `bad` (INTEGER). Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Bug 2 Phase 2.4: set_repo_status must write the reason onto
-- workspaces.repo_error (the column the readiness gate reads) and NOT
-- users.repo_error (the 108 split-write the member loops on — AC6c).

-- (1) set_repo_status(uuid,text,text) still exists and is EXECUTABLE by
--     `authenticated` (the tenant .rpc() call site).
SELECT 'set_repo_status_not_executable_by_authenticated' AS check_name,
       (NOT has_function_privilege(
          'authenticated',
          'public.set_repo_status(uuid, text, text)',
          'EXECUTE'))::int AS bad
UNION ALL
-- (2) the function body WRITES workspaces.repo_error (the gate's source of truth).
SELECT 'set_repo_status_missing_workspaces_repo_error_write',
       (position('repo_error' IN
          pg_get_functiondef('public.set_repo_status(uuid, text, text)'::regprocedure)) = 0)::int AS bad
UNION ALL
-- (3) the function body NO LONGER touches public.users (the split-write the
--     member-triggered heal looped on). A residual `users` write means the AC6c
--     fix regressed.
SELECT 'set_repo_status_still_writes_users',
       (position('users' IN
          pg_get_functiondef('public.set_repo_status(uuid, text, text)'::regprocedure)) > 0)::int AS bad;
