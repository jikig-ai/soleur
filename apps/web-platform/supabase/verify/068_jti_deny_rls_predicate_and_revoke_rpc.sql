-- Verify 068_jti_deny_rls_predicate_and_revoke_rpc.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 068:
--   * revoke_jti(uuid, uuid, text) exists, SECURITY DEFINER.
--   * my_revocation_status() exists, SECURITY DEFINER.
--   * is_jti_denied_from_jwt() exists, SECURITY DEFINER, STABLE.
--   * is_jti_denied(uuid) is now GRANTed EXECUTE TO authenticated.
--   * revoke_jti is NOT granted to authenticated (service-role-only).
--   * my_revocation_status is granted TO authenticated.
--   * Exactly 19 RESTRICTIVE policies named *_jti_not_denied exist.
--   * Each of the 19 tenant tables has its own policy.

-- (1) revoke_jti present + SECURITY DEFINER
SELECT 'revoke_jti_fn_present' AS check_name,
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int AS bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'revoke_jti'
   AND p.prosecdef = true
UNION ALL
-- (2) my_revocation_status present + SECURITY DEFINER
SELECT 'my_revocation_status_fn_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'my_revocation_status'
   AND p.prosecdef = true
UNION ALL
-- (3) is_jti_denied_from_jwt present + SECURITY DEFINER + STABLE
SELECT 'is_jti_denied_from_jwt_fn_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'is_jti_denied_from_jwt'
   AND p.prosecdef = true
   AND p.provolatile = 's'
UNION ALL
-- (4) is_jti_denied(uuid) is now GRANTed EXECUTE TO authenticated
SELECT 'is_jti_denied_authenticated_grant_present',
       CASE WHEN has_function_privilege(
              'authenticated',
              'public.is_jti_denied(uuid)',
              'EXECUTE'
            ) THEN 0 ELSE 1 END::int
UNION ALL
-- (5) revoke_jti is NOT granted to authenticated
SELECT 'revoke_jti_authenticated_revoke_present',
       CASE WHEN has_function_privilege(
              'authenticated',
              'public.revoke_jti(uuid, uuid, text)',
              'EXECUTE'
            ) THEN 1 ELSE 0 END::int
UNION ALL
-- (6) my_revocation_status IS granted to authenticated
SELECT 'my_revocation_status_authenticated_grant_present',
       CASE WHEN has_function_privilege(
              'authenticated',
              'public.my_revocation_status()',
              'EXECUTE'
            ) THEN 0 ELSE 1 END::int
UNION ALL
-- (7) Exactly 19 RESTRICTIVE jti_not_denied policies
SELECT 'jti_deny_policies_count_19',
       CASE WHEN count(*) = 19 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public'
   AND policyname LIKE '%_jti_not_denied'
   AND permissive = 'RESTRICTIVE'
UNION ALL
-- (8-26) Per-table presence assertions (one row per tenant table)
SELECT 'conversations_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='conversations'
   AND policyname='conversations_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'messages_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='messages'
   AND policyname='messages_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'users_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='users'
   AND policyname='users_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'api_keys_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='api_keys'
   AND policyname='api_keys_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'audit_byok_use_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='audit_byok_use'
   AND policyname='audit_byok_use_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'scope_grants_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='scope_grants'
   AND policyname='scope_grants_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'audit_github_token_use_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='audit_github_token_use'
   AND policyname='audit_github_token_use_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'kb_share_links_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='kb_share_links'
   AND policyname='kb_share_links_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'push_subscriptions_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions'
   AND policyname='push_subscriptions_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'user_concurrency_slots_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='user_concurrency_slots'
   AND policyname='user_concurrency_slots_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'dsar_export_jobs_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='dsar_export_jobs'
   AND policyname='dsar_export_jobs_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'action_sends_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='action_sends'
   AND policyname='action_sends_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'template_authorizations_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='template_authorizations'
   AND policyname='template_authorizations_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'byok_delegations_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='byok_delegations'
   AND policyname='byok_delegations_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'workspaces_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='workspaces'
   AND policyname='workspaces_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'workspace_members_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='workspace_members'
   AND policyname='workspace_members_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'workspace_member_attestations_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='workspace_member_attestations'
   AND policyname='workspace_member_attestations_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'user_session_state_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='user_session_state'
   AND policyname='user_session_state_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'message_attachments_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='message_attachments'
   AND policyname='message_attachments_jti_not_denied' AND permissive='RESTRICTIVE';
