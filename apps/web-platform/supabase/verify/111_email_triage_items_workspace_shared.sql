-- Verify 111_email_triage_items_workspace_shared.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 111 (workspace grain):
--   * email_triage_items.workspace_id column exists
--   * the SELECT policy is the workspace-owner policy (old user_id policy gone)
--   * still NO INSERT/UPDATE/DELETE policies (writes RPC/service-role only)
--   * is_email_triage_workspace_owner exists, SECURITY DEFINER, EXECUTE-able by
--     authenticated but NOT anon
--   * set_email_triage_status still EXECUTE-able by authenticated, NOT anon

-- (1) workspace_id column exists
SELECT 'email_triage_items_workspace_id_column_exists' AS check_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'email_triage_items'
           AND column_name = 'workspace_id'
       ) THEN 0 ELSE 1 END::int AS bad
UNION ALL
-- (2) workspace-owner SELECT policy present
SELECT 'email_triage_items_workspace_owner_select_present',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_policy p
         JOIN pg_class c ON c.oid = p.polrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'email_triage_items'
           AND p.polname = 'email_triage_items_workspace_owner_select'
           AND p.polcmd = 'r'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (3) old user_id SELECT policy removed
SELECT 'email_triage_items_old_user_id_policy_removed',
       (SELECT count(*) FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'email_triage_items'
          AND p.polname = 'email_triage_items_owner_select')::int
UNION ALL
-- (4) still no INSERT/UPDATE/DELETE policies
SELECT 'email_triage_items_no_write_policies',
       (SELECT count(*) FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'email_triage_items'
          AND p.polcmd IN ('a', 'w', 'd'))::int
UNION ALL
-- (5) helper exists and is SECURITY DEFINER
SELECT 'is_email_triage_workspace_owner_security_definer',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc pr
         JOIN pg_namespace n ON n.oid = pr.pronamespace
         WHERE n.nspname = 'public'
           AND pr.proname = 'is_email_triage_workspace_owner'
           AND pr.prosecdef
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (6) helper EXECUTE-able by authenticated
SELECT 'is_email_triage_workspace_owner_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.is_email_triage_workspace_owner(uuid, uuid)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (7) helper NOT EXECUTE-able by anon
SELECT 'is_email_triage_workspace_owner_not_granted_to_anon',
       CASE WHEN has_function_privilege(
         'anon',
         'public.is_email_triage_workspace_owner(uuid, uuid)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (8) set_email_triage_status still EXECUTE-able by authenticated
SELECT 'set_email_triage_status_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.set_email_triage_status(uuid, text)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int;
