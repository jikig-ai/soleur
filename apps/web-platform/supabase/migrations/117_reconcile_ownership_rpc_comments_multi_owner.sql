-- 117_reconcile_ownership_rpc_comments_multi_owner.sql
-- docs/metadata reconcile: multi-owner-by-design ownership RPCs (#5756 / ADR-072).
--
-- Workspaces support N co-owners by design (founder ruling #5733; ADR-072 is
-- the dedicated decision-of-record, superseding the single-owner-strict model
-- asserted by migration 075 / #4520 and resolving the long-standing ADR-038
-- (multi-owner) vs mig-075 (single-owner-strict) contradiction).
--
-- The running system ALREADY permits N owners end-to-end: workspace_members
-- has no UNIQUE/CHECK/EXCLUDE owner constraint; invite-as-owner is live;
-- update_workspace_member_role (mig 094) permits member->owner promotion; and
-- transfer_workspace_ownership (mig 092) is a promote-before-demote hand-off
-- that is multi-owner-safe. The ONLY residual inconsistency this migration
-- fixes is the live COMMENT ON FUNCTION metadata, which still asserts
-- "Single-owner strict". This is a metadata-only change.
--
-- SCOPE: COMMENT ON FUNCTION ONLY. No CREATE / ALTER / GRANT / REVOKE / DROP /
-- UPDATE statement appears in this file. No function body is re-emitted (that
-- would risk the 092/094 COALESCE(p_caller_user_id, auth.uid()) +
-- service_role-only FORWARD-REFERENCE invariants). The two functions are
-- unchanged in definition and grant; only their human-readable comment text is
-- reconciled to the multi-owner model.
--
-- APPLY-ROLE: near-zero risk. Migrations 092:193 and 094:278 already
-- COMMENT ON FUNCTION these exact two functions and apply green; the apply role
-- created them (092:48, 094:184) and no later ALTER FUNCTION ... OWNER exists.
--
-- VERSION-PAIRED with verify/117 (locks the durable invariant) and
-- 117_*.down.sql (restores the prior comment text verbatim).

-- transfer_workspace_ownership: hand-off-and-step-down + primary-pointer.
-- Replaces the "Single-owner strict" assertion. transfer is NOT a single-owner
-- enforcer: it is the atomic hand-off that re-points the
-- organizations.owner_user_id primary/billing/DSAR pointer; co-owners are added
-- via invite-as-owner / update_workspace_member_role promotion, which do NOT
-- touch the pointer (ADR-072).
COMMENT ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid) IS
  'Atomic workspace ownership hand-off-and-step-down (multi-owner-by-design, '
  'ADR-072 / #5756). Promotes target to owner FIRST then demotes caller to '
  'member (promote-before-demote keeps the at-least-one-owner invariant); '
  're-points the organizations.owner_user_id primary/billing/DSAR pointer to '
  'the new owner; writes attestation + revocation rows. NOT the only owner path '
  'and NOT a single-owner enforcer — additional co-owners are granted via '
  'invite-as-owner or update_workspace_member_role promotion (neither touches '
  'the pointer). Caller resolved via COALESCE(p_caller_user_id, auth.uid()) for '
  'service-role invocation; service_role-only grant (forgeable override). '
  '#4520 / #4765.';

-- update_workspace_member_role: member->owner promotion is PERMITTED (the
-- additive co-owner primitive; the mig-075 promotion block is gone). The
-- retained count(owner) <= 1 guard is the at-least-one-owner invariant, the
-- only ownership-cardinality rule (ADR-072).
COMMENT ON FUNCTION public.update_workspace_member_role(uuid, uuid, text, uuid) IS
  'Workspace-member role-change RPC (mig 094 caller-override fix; multi-owner '
  'reconcile ADR-072 / #5756). Direct member->owner promotion is PERMITTED — '
  'the additive co-owner primitive (the single-owner-strict mig-075 promotion '
  'block is gone). The retained count(owner) <= 1 "cannot demote the last '
  'owner" guard is the at-least-one-owner invariant — the only '
  'ownership-cardinality rule. Caller resolved via '
  'COALESCE(p_caller_user_id, auth.uid()); service_role-only grant (forgeable '
  'override). Preserves owner-gate, invalid-role guard, self-mutate + '
  'last-owner-demote guards, audit GUC, revocation row, F6 session clear '
  '(mig 067 #4307).';
