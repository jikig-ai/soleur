-- 068_jti_deny_rls_predicate_and_revoke_rpc.down.sql
-- Rollback for 068_jti_deny_rls_predicate_and_revoke_rpc.sql.
--
-- Order (reverse of forward apply):
--   1. DROP the 21 RESTRICTIVE policies.
--   2. REVOKE EXECUTE on public.is_jti_denied(uuid) FROM authenticated
--      (restore the mig 037 baseline of service-role-only).
--   3. DROP the 3 SECURITY DEFINER functions.

DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'conversations',
    'messages',
    'users',
    'api_keys',
    'audit_byok_use',
    'scope_grants',
    'audit_github_token_use',
    'kb_share_links',
    'push_subscriptions',
    'user_concurrency_slots',
    'dsar_export_jobs',
    'action_sends',
    'template_authorizations',
    'byok_delegations',
    'workspaces',
    'workspace_members',
    'workspace_member_attestations',
    'user_session_state',
    'message_attachments',
    'organizations',
    'workspace_member_removals'
  ];
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I_jti_not_denied ON public.%I',
      t, t
    );
  END LOOP;
END $$;

REVOKE EXECUTE ON FUNCTION public.is_jti_denied(uuid) FROM authenticated;

DROP FUNCTION IF EXISTS public.is_jti_denied_from_jwt();
DROP FUNCTION IF EXISTS public.my_revocation_status();
DROP FUNCTION IF EXISTS public.revoke_jti(uuid, uuid, text);
