-- 117_reconcile_ownership_rpc_comments_multi_owner.down.sql
-- Manual-rollback artifact for 117 (the Supabase pipeline is forward-only).
--
-- Restores the PRIOR COMMENT ON FUNCTION text VERBATIM — the exact string
-- values from migration 092:193-198 (transfer) and 094:278-283 (update). Note
-- 092's original comment was a multi-line adjacent-string-literal concatenation
-- with NO inserted space between '...organizations.' and 'owner_user_id...';
-- the line breaks below differ but the FINAL concatenated string value is
-- identical (PostgreSQL concatenates adjacent string literals).
--
-- VERSION-PAIRED with verify/117: rolling 117 back re-installs the
-- "Single-owner strict" transfer COMMENT, which would red verify/117's
-- secondary check 5 (transfer-comment-not-single-owner-strict) if that sentinel
-- stayed applied. This is fine — the Supabase pipeline is forward-only and down
-- files are manual-rollback artifacts; a manual 117 rollback also rolls back
-- verify/117.

COMMENT ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid) IS
  'Atomic workspace ownership transfer. Single-owner strict: promotes '
  'target to owner, demotes caller to member, updates organizations.'
  'owner_user_id, writes attestation + revocation rows. Caller resolved via '
  'COALESCE(p_caller_user_id, auth.uid()) for service-role invocation; '
  'service_role-only grant (forgeable override). #4520 / #4765.';

COMMENT ON FUNCTION public.update_workspace_member_role(uuid, uuid, text, uuid) IS
  'Workspace-member role-change RPC (mig 094 caller-override fix). Caller '
  'resolved via COALESCE(p_caller_user_id, auth.uid()); service_role-only '
  'grant (forgeable override). Preserves owner-gate, invalid-role guard, '
  'self-mutate + last-owner-demote guards, audit GUC, revocation row, F6 '
  'session clear (mig 067 #4307).';
