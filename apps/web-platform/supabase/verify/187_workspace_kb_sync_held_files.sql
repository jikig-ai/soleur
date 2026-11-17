-- verify/187_workspace_kb_sync_held_files.sql
-- Runtime catalog sentinel for migration 187 (#12714, D29(10)). The migration-shape test
-- (test/supabase-migrations/187-workspace-kb-sync-held-files.test.ts) asserts the SQL TEXT; this asserts the LIVE
-- catalog after apply. Each row returns bad=1 on a drift. Like verify/186, the release pipeline does not run this
-- file today (verify-migrations is skipped on workflow_run deploys, trackers #9825 and #9471): run it by hand with
-- run-verify.sh when the catalog must be proven.
--
-- Invariants:
--   * `authenticated` has no SELECT on either new column (174's column-split SELECT does not name them). The
--     table-level INSERT/UPDATE from 174 is NOT checked here: it remains by design and RLS is the barrier.
--   * the RPC is SECURITY DEFINER with search_path pinned to public, pg_temp, STABLE, member-checked on auth.uid(),
--     EXECUTE-able by authenticated and not by anon.
--   * no other function of that name exists in public (no leftover overload).

SELECT 'held_files_authenticated_no_select' AS check_name,
       CASE WHEN has_column_privilege('authenticated','public.workspaces','kb_sync_held_files','SELECT')
            THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'held_checked_at_authenticated_no_select',
       CASE WHEN has_column_privilege('authenticated','public.workspaces','kb_sync_held_checked_at','SELECT')
            THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'held_files_range_check_present',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint
                          WHERE conrelid = 'public.workspaces'::regclass
                            AND conname = 'workspaces_kb_sync_held_files_range'
                            AND contype = 'c')
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
SELECT 'get_kb_sync_held_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated','public.get_workspace_kb_sync_held(uuid)','EXECUTE')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_kb_sync_held_has_no_other_overloads',
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'get_workspace_kb_sync_held'
           AND p.oid <> 'public.get_workspace_kb_sync_held(uuid)'::regprocedure)::int;
