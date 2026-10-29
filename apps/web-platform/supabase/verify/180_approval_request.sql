-- verify/180_approval_request.sql
-- Runtime catalog sentinel for the approval_request table and RPCs (#4672 slice 1). The migration-shape test
-- (test/approval/migration-180-approval-request.test.ts) asserts the SQL TEXT; this asserts the LIVE catalog after
-- apply. Each row returns bad=1 on a drift; run-verify.sh fails the deploy if any bad=1 (precedent: verify/177).
--
-- Invariants: the table is RLS-enabled with exactly one permissive policy (Owner SELECT) and no write policy, no api
-- role holds a write privilege and service_role holds none at all; every RPC is SECURITY DEFINER with search_path
-- pinned; decide_approval is EXECUTE-able by authenticated ONLY, every other RPC by service_role ONLY; the internal
-- helper and the guard trigger function are EXECUTE-able by nobody (no PUBLIC, no api role); the write-once guard
-- trigger exists and is enabled; exactly one CHECK on inbox_item references `source` and it admits approval_required;
-- the revoke columns, the cap/scrub/FK indexes and the principal re-check, erasure-delete and cap clauses are present.
-- There is deliberately NO row-level "no approval row survives for an erased solo workspace" check here: a memberless
-- TEAM workspace (every member erased, accepted residual) is indistinguishable from an erased personal workspace by
-- catalog query and would fail verify-migrations on every later release. The falsifier lives in
-- test/server/approval-request.tenant-isolation.test.ts (solo case deleted; sole-member team case retained).

SELECT 'approval_request_rls_enabled' AS check_name,
       CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.approval_request'::regclass) THEN 0 ELSE 1 END::int AS bad
UNION ALL
SELECT 'approval_request_one_permissive_policy_select_only',
       CASE WHEN (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'approval_request' AND permissive = 'PERMISSIVE') = 1
            AND (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'approval_request' AND permissive = 'PERMISSIVE' AND cmd = 'SELECT') = 1
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_anon_insert_revoked',
       CASE WHEN has_table_privilege('anon', 'public.approval_request', 'INSERT') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_anon_update_revoked',
       CASE WHEN has_table_privilege('anon', 'public.approval_request', 'UPDATE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_anon_delete_revoked',
       CASE WHEN has_table_privilege('anon', 'public.approval_request', 'DELETE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_anon_truncate_revoked',
       CASE WHEN has_table_privilege('anon', 'public.approval_request', 'TRUNCATE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_authenticated_insert_revoked',
       CASE WHEN has_table_privilege('authenticated', 'public.approval_request', 'INSERT') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_authenticated_update_revoked',
       CASE WHEN has_table_privilege('authenticated', 'public.approval_request', 'UPDATE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_authenticated_delete_revoked',
       CASE WHEN has_table_privilege('authenticated', 'public.approval_request', 'DELETE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_authenticated_truncate_revoked',
       CASE WHEN has_table_privilege('authenticated', 'public.approval_request', 'TRUNCATE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_service_role_insert_revoked',
       CASE WHEN has_table_privilege('service_role', 'public.approval_request', 'INSERT') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_service_role_update_revoked',
       CASE WHEN has_table_privilege('service_role', 'public.approval_request', 'UPDATE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_service_role_delete_revoked',
       CASE WHEN has_table_privilege('service_role', 'public.approval_request', 'DELETE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_service_role_truncate_revoked',
       CASE WHEN has_table_privilege('service_role', 'public.approval_request', 'TRUNCATE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_anon_select_revoked',
       CASE WHEN has_table_privilege('anon', 'public.approval_request', 'SELECT') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_service_role_select_revoked',
       CASE WHEN has_table_privilege('service_role', 'public.approval_request', 'SELECT') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_authenticated_select_granted',
       CASE WHEN has_table_privilege('authenticated', 'public.approval_request', 'SELECT') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_guard_trigger_enabled',
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.approval_request'::regclass AND tgname = 'approval_request_guard' AND tgenabled = 'O') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_live_unique_index_exists',
       CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'approval_request_live_uniq' AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%pending%') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'inbox_item_source_admits_approval_required',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.inbox_item'::regclass AND conname = 'inbox_item_source_check' AND convalidated AND pg_get_constraintdef(oid) LIKE '%approval_required%') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'create_approval_request_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'create_approval_request_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'create_approval_request_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'create_approval_request_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'create_approval_request_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'create_approval_request_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)'::regprocedure, 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'decide_approval_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.decide_approval(uuid, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'decide_approval_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.decide_approval(uuid, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'decide_approval_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.decide_approval(uuid, text)'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'decide_approval_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.decide_approval(uuid, text)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'decide_approval_authenticated_granted',
       CASE WHEN has_function_privilege('authenticated', 'public.decide_approval(uuid, text)'::regprocedure, 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'decide_approval_service_role_revoked',
       CASE WHEN has_function_privilege('service_role', 'public.decide_approval(uuid, text)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'consume_approval_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.consume_approval(uuid, text, uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'consume_approval_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.consume_approval(uuid, text, uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'consume_approval_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.consume_approval(uuid, text, uuid)'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'consume_approval_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.consume_approval(uuid, text, uuid)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'consume_approval_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.consume_approval(uuid, text, uuid)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'consume_approval_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.consume_approval(uuid, text, uuid)'::regprocedure, 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_approval_status_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.get_approval_status(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_approval_status_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.get_approval_status(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_approval_status_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.get_approval_status(uuid)'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'get_approval_status_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.get_approval_status(uuid)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'get_approval_status_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.get_approval_status(uuid)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'get_approval_status_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.get_approval_status(uuid)'::regprocedure, 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'list_live_approvals_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.list_live_approvals(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'list_live_approvals_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.list_live_approvals(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'list_live_approvals_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.list_live_approvals(uuid)'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'list_live_approvals_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.list_live_approvals(uuid)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'list_live_approvals_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.list_live_approvals(uuid)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'list_live_approvals_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.list_live_approvals(uuid)'::regprocedure, 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'sweep_approvals_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.sweep_approvals()'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'sweep_approvals_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.sweep_approvals()'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'sweep_approvals_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.sweep_approvals()'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'sweep_approvals_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.sweep_approvals()'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'sweep_approvals_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.sweep_approvals()'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'sweep_approvals_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.sweep_approvals()'::regprocedure, 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'anonymise_approval_request_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.anonymise_approval_request(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'anonymise_approval_request_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.anonymise_approval_request(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'anonymise_approval_request_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.anonymise_approval_request(uuid)'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'anonymise_approval_request_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.anonymise_approval_request(uuid)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'anonymise_approval_request_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.anonymise_approval_request(uuid)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'anonymise_approval_request_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.anonymise_approval_request(uuid)'::regprocedure, 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_guard_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.approval_request_guard()'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_guard_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.approval_request_guard()'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_guard_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.approval_request_guard()'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_guard_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.approval_request_guard()'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_guard_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.approval_request_guard()'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_guard_service_role_revoked',
       CASE WHEN has_function_privilege('service_role', 'public.approval_request_guard()'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_inbox_settle_is_definer',
       CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.approval_request_inbox_settle(uuid, uuid, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_inbox_settle_search_path_pinned',
       CASE WHEN (SELECT proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%pg_temp%') FROM pg_proc WHERE oid = 'public.approval_request_inbox_settle(uuid, uuid, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_inbox_settle_public_revoked',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = 'public.approval_request_inbox_settle(uuid, uuid, text)'::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_inbox_settle_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.approval_request_inbox_settle(uuid, uuid, text)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_inbox_settle_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.approval_request_inbox_settle(uuid, uuid, text)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'approval_request_inbox_settle_service_role_revoked',
       CASE WHEN has_function_privilege('service_role', 'public.approval_request_inbox_settle(uuid, uuid, text)'::regprocedure, 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'create_approval_request_refuses_user_identity',
       CASE WHEN (SELECT prosrc LIKE '%auth.uid() IS NOT NULL%' FROM pg_proc WHERE oid = 'public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'consume_approval_refuses_user_identity',
       CASE WHEN (SELECT prosrc LIKE '%auth.uid() IS NOT NULL%' FROM pg_proc WHERE oid = 'public.consume_approval(uuid, text, uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'get_approval_status_refuses_user_identity',
       CASE WHEN (SELECT prosrc LIKE '%auth.uid() IS NOT NULL%' FROM pg_proc WHERE oid = 'public.get_approval_status(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'list_live_approvals_refuses_user_identity',
       CASE WHEN (SELECT prosrc LIKE '%auth.uid() IS NOT NULL%' FROM pg_proc WHERE oid = 'public.list_live_approvals(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'sweep_approvals_refuses_user_identity',
       CASE WHEN (SELECT prosrc LIKE '%auth.uid() IS NOT NULL%' FROM pg_proc WHERE oid = 'public.sweep_approvals()'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'decide_approval_checks_owner_and_jti',
       CASE WHEN (SELECT prosrc LIKE '%is_workspace_owner(v_ws, auth.uid())%' AND prosrc LIKE '%is_jti_denied_from_jwt()%' FROM pg_proc WHERE oid = 'public.decide_approval(uuid, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'decide_approval_owner_check_before_row_lock',
       CASE WHEN (SELECT position('is_workspace_owner(v_ws' IN prosrc) > 0 AND position('is_workspace_owner(v_ws' IN prosrc) < position('FOR UPDATE' IN prosrc) FROM pg_proc WHERE oid = 'public.decide_approval(uuid, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'decide_approval_has_revoke_path',
       CASE WHEN (SELECT prosrc LIKE '%revoked_by = auth.uid()%' AND prosrc LIKE '%''revoked''%' FROM pg_proc WHERE oid = 'public.decide_approval(uuid, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'consume_approval_predicate_complete',
       CASE WHEN (SELECT prosrc LIKE '%status = ''approved''%' AND prosrc LIKE '%expires_at > now()%' AND prosrc LIKE '%action_sha256 = p_hash%' AND prosrc LIKE '%conversation_id = p_conversation%' FROM pg_proc WHERE oid = 'public.consume_approval(uuid, text, uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'consume_approval_principal_recheck',
       CASE WHEN (SELECT prosrc LIKE '%AND public.is_workspace_owner(workspace_id, decided_by)%' AND prosrc LIKE '%AND public.is_workspace_member(workspace_id, requested_by_user_id)%' AND prosrc LIKE '%decider_not_owner%' AND prosrc LIKE '%requester_not_member%' FROM pg_proc WHERE oid = 'public.consume_approval(uuid, text, uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'create_approval_request_has_pending_caps',
       CASE WHEN (SELECT prosrc LIKE '%AP429%' AND prosrc LIKE '%AP430%' AND prosrc LIKE '%''notify''%' FROM pg_proc WHERE oid = 'public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'anonymise_approval_request_deletes_memberless_workspace_rows',
       CASE WHEN (SELECT prosrc LIKE '%app.approval_erase%' AND prosrc LIKE '%DELETE FROM public.approval_request WHERE workspace_id = p_user_id%' AND prosrc LIKE '%NOT EXISTS (SELECT 1 FROM public.workspace_members WHERE workspace_id = p_user_id)%' FROM pg_proc WHERE oid = 'public.anonymise_approval_request(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_guard_delete_erase_carveout',
       CASE WHEN (SELECT prosrc LIKE '%app.approval_erase%' AND prosrc LIKE '%NOT EXISTS (SELECT 1 FROM public.workspace_members WHERE workspace_id = OLD.workspace_id)%' FROM pg_proc WHERE oid = 'public.approval_request_guard()'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_revoke_columns_exist',
       CASE WHEN (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'approval_request' AND column_name IN ('revoked_at', 'revoked_by')) = 2
            AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.approval_request'::regclass AND conname = 'approval_request_revoked_pairing' AND convalidated)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'approval_request_support_indexes_exist',
       CASE WHEN (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'approval_request'
                    AND indexname IN ('approval_request_ws_pending_idx', 'approval_request_scrub_idx', 'approval_request_requested_by_idx',
                                      'approval_request_decided_by_idx', 'approval_request_revoked_by_idx')) = 5 THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'inbox_item_source_only_admitting_check',
       CASE WHEN (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.inbox_item'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) ~ '\ysource\y') = 1
            AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.inbox_item'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) ~ '\ysource\y' AND pg_get_constraintdef(oid) NOT LIKE '%approval_required%')
            THEN 0 ELSE 1 END::int;
