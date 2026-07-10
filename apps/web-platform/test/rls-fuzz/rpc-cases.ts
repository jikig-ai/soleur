// SECURITY DEFINER RPC-bypass classification (#6256, ADR-103, AC8).
//
// Every `SECURITY DEFINER` fn that `authenticated` may EXECUTE (catalog.ts) must
// appear in EXACTLY ONE of the three maps below — the coverage gate asserts
// `keys(ATTACK) ∪ keys(EXCLUDED) ∪ keys(KNOWN_EXPOSURES) == catalog set` and fails
// on any uncovered fn (self-tracking: a new definer fn granted to authenticated
// reds the suite until classified).
//
//  - ATTACK: driven with tenant-B claims + tenant-A params; MUST deny (throw, or
//    return null/false/empty/0-rows). A fn that returns A's data or a non-empty
//    result = a bypass = leaked.
//  - EXCLUDED: no workspace-tenancy param to forge — the fn keys entirely on
//    `auth.uid()` (self-scoped) or a non-workspace global namespace (recipient
//    suppression), or is a trigger fn not callable directly. Rationale required.
//  - KNOWN_EXPOSURES: the fn DOES leak cross-tenant today (harness found it); the
//    denial assertion is run under `test.fails` and references the tracking issue,
//    so the suite stays green while the exposure is tracked — and flips RED (via a
//    now-passing assertion) the moment the grant is fixed, forcing un-baselining.

import type { Ctx } from "./targets";

/** Extended fixture: A-owned resource ids the RPC attacks address. */
export interface RpcCtx extends Ctx {
  kbFileA: string;
  messageA: string;
  delegationA: string;
  /** An A-owned beta-CRM contact (crm_contact_set_stage / crm_note_append target). */
  contactA: string;
  /** An A-owned inbox item, pinned to user_id=userA (set_inbox_item_state target). */
  inboxA: string;
}

/**
 * ATTACK cases — each SQL is executed under tenant-B claims and must DENY.
 * SQL returns a single classifiable scalar (null/false/0 = denied) or throws
 * (a membership/ownership guard rejecting the cross-tenant caller = denied).
 */
export const ATTACK_SQL: Record<string, (c: RpcCtx) => string> = {
  // workspace-tenancy param → membership guard raises 42501 / owner error, or getter returns null
  set_repo_status: (c) => `select set_repo_status('${c.wsA}','ready',null)`,
  set_current_workspace_id: (c) => `select set_current_workspace_id('${c.wsA}')`,
  set_workspace_autonomous_ack: (c) => `select set_workspace_autonomous_ack('${c.wsA}')`,
  set_workspace_bash_autonomous: (c) => `select set_workspace_bash_autonomous('${c.wsA}',true)`,
  set_workspace_debug_mode: (c) => `select set_workspace_debug_mode('${c.wsA}',true)`,
  get_workspace_autonomous_ack: (c) => `select get_workspace_autonomous_ack('${c.wsA}')`,
  get_workspace_bash_autonomous: (c) => `select get_workspace_bash_autonomous('${c.wsA}')`,
  get_workspace_debug_mode: (c) => `select get_workspace_debug_mode('${c.wsA}')`,
  resolve_workspace_installation_id: (c) => `select resolve_workspace_installation_id('${c.wsA}')`,
  claim_repo_clone_lock: (c) => `select claim_repo_clone_lock('${c.wsA}')`,
  is_workspace_member: (c) => `select is_workspace_member('${c.wsA}', auth.uid())`,
  is_workspace_owner: (c) => `select is_workspace_owner('${c.wsA}', auth.uid())`,
  is_email_triage_workspace_owner: (c) => `select is_email_triage_workspace_owner('${c.wsA}', auth.uid())`,
  list_workspace_member_actions: (c) => `select count(*) from list_workspace_member_actions('${c.wsA}',10,null,null)`,
  invite_workspace_member: (c) =>
    `select invite_workspace_member('${c.wsA}', auth.uid(), 'attestation-16-chars-min','iphash','ua')`,
  grant_byok_delegation: (c) =>
    `select grant_byok_delegation('${c.userA}','${c.userB}','${c.wsA}',1000,100,null,'${c.userB}')`,
  // resource-id param owned by A → ownership guard raises, or predicate returns false
  set_conversation_visibility: (c) => `select set_conversation_visibility('${c.convA}','private')`,
  set_kb_file_visibility: (c) => `select set_kb_file_visibility('${c.kbFileA}','workspace')`,
  is_message_owner: (c) => `select is_message_owner('${c.messageA}', auth.uid())`,
  is_attachment_path_workspace_member: (c) => `select is_attachment_path_workspace_member('${c.convA}', auth.uid())`,
  revoke_byok_delegation: (c) => `select revoke_byok_delegation('${c.delegationA}', auth.uid(), 'admin_revoke')`,
  update_byok_delegation_cap: (c) => `select update_byok_delegation_cap('${c.delegationA}',500,50, auth.uid())`,
  withdraw_byok_delegation_consent: (c) => `select withdraw_byok_delegation_consent('${c.delegationA}')`,
  // Real A-owned resources so the OWNERSHIP guard (not a NOT-FOUND/validation
  // error) is what rejects tenant-B — otherwise the case is vacuous (F2).
  crm_contact_set_stage: (c) => `select crm_contact_set_stage('${c.contactA}','contacted')`,
  crm_note_append: (c) => `select crm_note_append('${c.contactA}','body',ARRAY['sales'],null)`,
  set_inbox_item_state: (c) => `select set_inbox_item_state('${c.inboxA}','archived')`,
  // self-target GDPR fns that MUST reject a non-self caller (they take p_user_id)
  anonymise_action_sends: (c) => `select anonymise_action_sends('${c.userA}')`,
  anonymise_template_authorizations: (c) => `select anonymise_template_authorizations('${c.userA}')`,
};

/** EXCLUDED — no workspace-tenancy param to forge; covered with rationale (AC8). */
export const EXCLUDED: Record<string, string> = {
  // self-scoped: key entirely on auth.uid(); no caller-supplied tenancy param
  grant_action_class: "founder_id = auth.uid(); grants a scope to the CALLER only",
  revoke_action_class: "founder_id = auth.uid(); revokes the CALLER's own scope",
  revoke_template_authorization: "template auths are founder-scoped by auth.uid(); no A-addressable param",
  authorize_template: "founder_id = auth.uid(); the fn writes the CALLER's own template_authorization row (p_grant_id is a cross-ref, not a base cross-tenant read/write) — deepen in the harness-hardening follow-up",
  set_email_triage_status: "email_triage_items is the single-founder operator inbox (resend ingest), not multi-tenant workspace data; a faithful attack needs the full ingest fixture — deepen in the harness-hardening follow-up",
  crm_contact_upsert: "founder_id = auth.uid(); p_id resolves within the caller's own founder scope (insert-if-not-owned)",
  check_my_revocation: "self-only (p_jwt_iat is the caller's own token iat)",
  my_revocation_status: "self-only; reads auth.uid()'s revocation state, no params",
  is_jti_denied_from_jwt: "reads the caller's own request.jwt.claims jti; no tenancy param",
  set_current_organization_id: "sets the CALLER's own current-org session pointer (user_session_state for auth.uid())",
  append_kb_sync_row: "appends to the caller's own kb-sync log; p_row is the caller's payload, no A-addressable id",
  // global (non-workspace) namespace: recipient-hash suppression is cross-tenant BY DESIGN (a shared send-dedup ledger)
  is_recipient_suppressed: "global recipient-hash suppression namespace; not workspace-tenant scoped",
  outbound_send_exists: "global recipient-hash / body-sha dedup namespace; not workspace-tenant scoped",
  record_outbound_send: "global recipient-hash send ledger; not workspace-tenant scoped",
  suppress_recipient: "global recipient-hash suppression ledger; not workspace-tenant scoped",
  // trigger function — not meaningfully callable with cross-tenant params
  release_slot_on_archive: "AFTER-trigger function on conversations; not a directly-callable RPC surface",
};

/**
 * KNOWN_EXPOSURES — the fn leaks cross-tenant TODAY. Same residual-grant root
 * cause: the migration granted EXECUTE to `service_role` only, but Supabase's
 * default privileges left `authenticated` (and `anon`) an EXECUTE grant, and the
 * fn trusts caller-supplied params without an `auth.uid()` check. Tracked by the
 * issue; asserted under `test.fails` (green while exposed, RED once fixed).
 */
export const KNOWN_EXPOSURES: Record<string, { issue: string; note: string }> = {
  find_stuck_active_conversations: {
    issue: "#6306",
    note: "returns (id,user_id) for ALL tenants' stuck conversations to any authenticated/anon caller",
  },
  acquire_conversation_slot: {
    issue: "#6306",
    note: "trusts p_user_id → an authenticated caller can occupy/exhaust ANOTHER tenant's concurrency slots",
  },
  release_conversation_slot: {
    issue: "#6306",
    note: "trusts p_user_id → an authenticated caller can delete ANOTHER tenant's concurrency slot",
  },
  touch_conversation_slot: {
    issue: "#6306",
    note: "trusts p_user_id → an authenticated caller can keep-alive ANOTHER tenant's concurrency slot",
  },
};
