-- Verify 068_attachments_workspace_shared.sql.
--
-- Contract (see scripts/run-verify.sh): every row returns `check_name`
-- + `bad`. Any row with `bad > 0` fails the CI verify-migrations job.
--
-- Sentinels verify post-apply structural invariants from migration 068
-- (#4318 — workspace-shared attachments storage RLS + cascade RPCs):
--   * is_attachment_path_workspace_member(uuid, uuid) exists, SECURITY
--     DEFINER, pinned search_path, plpgsql, EXECUTE granted to
--     authenticated
--   * _anonymise_authored_messages_internal(uuid, uuid) exists with no
--     public GRANT (REVOKE-only matrix)
--   * anonymise_departed_user_across_workspaces(uuid) exists with
--     EXECUTE granted to service_role
--   * remove_workspace_member(uuid, uuid) body references
--     _anonymise_authored_messages_internal (the inserted call)
--   * Four new storage.objects policies present (SELECT widened +
--     INSERT/UPDATE/DELETE narrow); mig 045 FOR ALL policy gone
--   * No orphan-shape paths in chat-attachments (OQ5 audit)
--
-- Single-user-incident threshold per plan §User-Brand Impact —
-- any sentinel firing post-apply is a P0 page.

-- (1) Helper function exists with correct signature and SECURITY DEFINER.
SELECT 'is_attachment_path_workspace_member_present' AS check_name,
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int AS bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'is_attachment_path_workspace_member'
   AND p.prosecdef = true
UNION ALL
-- (2) Helper is plpgsql (NOT sql) — defeats planner inlining.
SELECT 'is_attachment_path_workspace_member_plpgsql',
       CASE WHEN l.lanname = 'plpgsql' THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language l ON l.oid = p.prolang
 WHERE n.nspname = 'public'
   AND p.proname = 'is_attachment_path_workspace_member'
UNION ALL
-- (3) Helper has search_path = public, pg_temp.
SELECT 'is_attachment_path_workspace_member_search_path',
       CASE WHEN array_to_string(p.proconfig, ',') ~ 'search_path=public, pg_temp'
            THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'is_attachment_path_workspace_member'
UNION ALL
-- (4) Helper EXECUTE granted to authenticated.
SELECT 'is_attachment_path_workspace_member_authenticated_grant',
       CASE WHEN has_function_privilege('authenticated',
                 'public.is_attachment_path_workspace_member(uuid, uuid)',
                 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
-- (5) Internal helper exists with NO public grant.
SELECT '_anonymise_authored_messages_internal_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = '_anonymise_authored_messages_internal'
   AND p.prosecdef = true
UNION ALL
-- (6) Internal helper NOT EXECUTABLE by authenticated nor service_role.
SELECT '_anonymise_authored_messages_internal_no_public_grant',
       CASE WHEN has_function_privilege('authenticated',
                 'public._anonymise_authored_messages_internal(uuid, uuid)',
                 'EXECUTE')
              OR has_function_privilege('service_role',
                 'public._anonymise_authored_messages_internal(uuid, uuid)',
                 'EXECUTE')
            THEN 1 ELSE 0 END::int
UNION ALL
-- (7) Public cascade RPC exists with service_role EXECUTE.
SELECT 'anonymise_departed_user_across_workspaces_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'anonymise_departed_user_across_workspaces'
   AND p.prosecdef = true
UNION ALL
SELECT 'anonymise_departed_user_across_workspaces_service_role_grant',
       CASE WHEN has_function_privilege('service_role',
                 'public.anonymise_departed_user_across_workspaces(uuid)',
                 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
-- (8) remove_workspace_member body references the cascade-call.
SELECT 'remove_workspace_member_calls_internal_cascade',
       CASE WHEN prosrc ~ '_anonymise_authored_messages_internal'
            THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'remove_workspace_member'
UNION ALL
-- (9-12) Four new storage.objects policies present (1 SELECT + 3 narrow writes).
SELECT 'storage_objects_co_member_select_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policy
 WHERE polrelid = 'storage.objects'::regclass
   AND polname = 'Users read own + co-member attachment objects'
UNION ALL
SELECT 'storage_objects_narrow_insert_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policy
 WHERE polrelid = 'storage.objects'::regclass
   AND polname = 'Users write own attachment objects only (insert)'
UNION ALL
SELECT 'storage_objects_narrow_update_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policy
 WHERE polrelid = 'storage.objects'::regclass
   AND polname = 'Users write own attachment objects only (update)'
UNION ALL
SELECT 'storage_objects_narrow_delete_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policy
 WHERE polrelid = 'storage.objects'::regclass
   AND polname = 'Users write own attachment objects only (delete)'
UNION ALL
-- (13) Old mig 045 FOR ALL policy GONE.
SELECT 'mig_045_for_all_policy_dropped',
       CASE WHEN count(*) = 0 THEN 0 ELSE 1 END::int
  FROM pg_policy
 WHERE polrelid = 'storage.objects'::regclass
   AND polname = 'Users can write own attachment objects'
UNION ALL
-- (14) OQ5 orphan-path audit: no malformed paths in chat-attachments.
SELECT 'chat_attachments_orphan_path_audit',
       COUNT(*)::int AS bad
  FROM storage.objects
 WHERE bucket_id = 'chat-attachments'
   AND ((storage.foldername(name))[1] IS NULL
     OR (storage.foldername(name))[1] !~ '^[0-9a-f-]{36}$'
     OR (storage.foldername(name))[2] IS NULL
     OR (storage.foldername(name))[2] !~ '^[0-9a-f-]{36}$')
UNION ALL
-- (15) PROBE-A re-verify: messages.workspace_id NULL count.
SELECT 'messages_workspace_id_null_count',
       COUNT(*)::int
  FROM public.messages
 WHERE workspace_id IS NULL;
