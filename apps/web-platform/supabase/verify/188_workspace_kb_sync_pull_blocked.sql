-- verify/188_workspace_kb_sync_pull_blocked.sql
-- Runtime catalog sentinel for migration 188 (#12714, D42, D45(c)). The migration-shape test
-- (test/supabase-migrations/188-workspace-kb-sync-pull-blocked.test.ts) asserts the SQL TEXT; this asserts the LIVE
-- catalog after apply. Each row returns bad=1 on a drift. Like verify/187, the release pipeline does not run this file
-- today (verify-migrations is skipped on workflow_run deploys, trackers #9825 and #9471): run it by hand with
-- run-verify.sh when the catalog must be proven. verify/187 keeps the rows that hold for 187 alone (the two older
-- columns, the anon barrier, the RPC's definer, path, member check and grants), which 188's recreate must also keep.
--
-- Invariants:
--   * `authenticated` has no SELECT on kb_sync_pull_blocked (174's column-split SELECT does not name it).
--   * the named closed-value check exists.
--   * the recreated RPC returns the three held columns, is SECURITY DEFINER with search_path pinned to public,
--     pg_temp, STABLE, member-checked on auth.uid(), EXECUTE-able by authenticated and not by anon or PUBLIC (a DROP
--     and CREATE resets the ACL, so 188's own REVOKE/GRANT is what these rows prove).

SELECT 'pull_blocked_authenticated_no_select' AS check_name,
       CASE WHEN has_column_privilege('authenticated','public.workspaces','kb_sync_pull_blocked','SELECT')
            THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'pull_blocked_values_check_present',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint
                          WHERE conrelid = 'public.workspaces'::regclass
                            AND conname = 'workspaces_kb_sync_pull_blocked_values'
                            AND contype = 'c')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_kb_sync_held_returns_three_columns',
       CASE WHEN (SELECT proargnames @> ARRAY['kb_sync_held_files','kb_sync_held_checked_at','kb_sync_pull_blocked']
                    FROM pg_proc WHERE oid = 'public.get_workspace_kb_sync_held(uuid)'::regprocedure)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_kb_sync_held_security_definer_search_path_pinned',
       CASE WHEN (SELECT prosecdef AND provolatile = 's' AND proconfig @> ARRAY['search_path=public, pg_temp']
                    FROM pg_proc WHERE oid = 'public.get_workspace_kb_sync_held(uuid)'::regprocedure)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_kb_sync_held_member_checked',
       CASE WHEN (SELECT prosrc LIKE '%is_workspace_member(p_workspace_id, auth.uid())%'
                    FROM pg_proc WHERE oid = 'public.get_workspace_kb_sync_held(uuid)'::regprocedure)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_kb_sync_held_anon_revoked',
       CASE WHEN has_function_privilege('anon','public.get_workspace_kb_sync_held(uuid)','EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'get_kb_sync_held_public_revoked',
       CASE WHEN has_function_privilege('public','public.get_workspace_kb_sync_held(uuid)','EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'get_kb_sync_held_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated','public.get_workspace_kb_sync_held(uuid)','EXECUTE')
            THEN 0 ELSE 1 END::int;
