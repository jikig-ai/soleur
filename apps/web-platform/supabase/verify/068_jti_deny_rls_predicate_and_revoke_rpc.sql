-- Verify 068_jti_deny_rls_predicate_and_revoke_rpc.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 068:
--   * revoke_jti(uuid, uuid, text) exists, SECURITY DEFINER.
--   * my_revocation_status() exists, SECURITY DEFINER.
--   * is_jti_denied_from_jwt() exists, SECURITY DEFINER, STABLE.
--   * is_jti_denied(uuid) GRANT-state superseded by mig 069 — see
--     verify/069_jti_deny_grant_restore.sql for the post-069 assertion
--     (REVOKED FROM authenticated, service_role only).
--   * revoke_jti is NOT granted to authenticated (service-role-only).
--   * my_revocation_status is granted TO authenticated.
--   * Exactly 26 RESTRICTIVE policies named *_jti_not_denied exist.
--   * Each of the 26 tenant tables has its own per-table presence
--     assertion (21 base from mig 068 + workspace_activity (mig 076)
--     + kb_files (mig 077) + beta_contacts / interview_notes /
--     beta_contact_stage_transitions (mig 126)) — so the named set
--     equals the aggregate count, not just the count.

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
-- is_jti_denied(uuid) EXECUTE grant — REMOVED at mig 069 time.
-- The original mig 068 check asserted authenticated had EXECUTE
-- (speculative belief that PostgREST evaluated RLS in the caller role
-- even through SECURITY DEFINER wrappers). Empirical testing at #4440
-- follow-up time proved that wrong: revoking the GRANT left
-- tenant-jwt-rls-deny.tenant-isolation.test.ts green. Mig 069 drops
-- the GRANT; verify/069_jti_deny_grant_restore.sql owns the
-- post-069 assertion (REVOKED FROM authenticated + anon + PUBLIC,
-- service_role retained). No no-op placeholder row here — no
-- row-counting harness depends on the count.
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
-- (7) Exactly 26 RESTRICTIVE jti_not_denied policies (21 base + workspace_activity
--     + kb_files from mig 076/077 + beta_contacts/interview_notes/beta_contact_stage_transitions from mig 126)
SELECT 'jti_deny_policies_count_26',
       CASE WHEN count(*) = 26 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public'
   AND policyname LIKE '%_jti_not_denied'
   AND permissive = 'RESTRICTIVE'
UNION ALL
-- (8-33) Per-table presence assertions (one row per tenant table; 26 total)
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
   AND policyname='message_attachments_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'organizations_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='organizations'
   AND policyname='organizations_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'workspace_member_removals_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='workspace_member_removals'
   AND policyname='workspace_member_removals_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
-- workspace_activity (mig 076)
SELECT 'workspace_activity_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='workspace_activity'
   AND policyname='workspace_activity_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
-- kb_files (mig 077)
SELECT 'kb_files_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='kb_files'
   AND policyname='kb_files_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
-- beta_contacts (mig 126)
SELECT 'beta_contacts_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='beta_contacts'
   AND policyname='beta_contacts_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
-- interview_notes (mig 126)
SELECT 'interview_notes_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='interview_notes'
   AND policyname='interview_notes_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
-- beta_contact_stage_transitions (mig 126)
SELECT 'beta_contact_stage_transitions_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='beta_contact_stage_transitions'
   AND policyname='beta_contact_stage_transitions_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
-- (34-36) anon-role REVOKE matrix: none of the three 068 functions
-- must be EXECUTE-able by anon. Pre-fix, the sentinel asserted only
-- the authenticated REVOKE matrix; an accidental future GRANT TO anon
-- (e.g. via PUBLIC) would slip past CI unobserved.
SELECT 'revoke_jti_anon_revoke_present',
       CASE WHEN has_function_privilege(
              'anon',
              'public.revoke_jti(uuid, uuid, text)',
              'EXECUTE'
            ) THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'my_revocation_status_anon_revoke_present',
       CASE WHEN has_function_privilege(
              'anon',
              'public.my_revocation_status()',
              'EXECUTE'
            ) THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'is_jti_denied_from_jwt_anon_revoke_present',
       CASE WHEN has_function_privilege(
              'anon',
              'public.is_jti_denied_from_jwt()',
              'EXECUTE'
            ) THEN 1 ELSE 0 END::int;
