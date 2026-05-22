// DSAR table allowlist + exclusions — Phase 5 of
// feat-dsar-art15-export-endpoint (issue #3637, plan rev-2).
//
// AC28 + S6: every public table with a column referencing
// auth.users (or public.users which cascades from auth.users) MUST be
// either in `DSAR_TABLE_ALLOWLIST` (exported as part of the bundle)
// or in `DSAR_TABLE_EXCLUSIONS` (with a documented reason). The
// file-parse lint `dsar-allowlist-completeness.test.ts` enforces this
// at CI time so a future migration adding a new user-FK table cannot
// silently widen Art. 15 completeness drift.
//
// FR8 + R10: the four legal documents (privacy-policy §4.7, GDPR
// policy §6.1.b, DPD §2.3 + §5.3, compliance-posture) MUST stay in
// sync with this allowlist. The cross-document CI gate
// (.github/workflows/legal-doc-cross-document-gate.yml — Phase 11)
// blocks merges that touch dsar-export.ts without touching all four
// legal docs.

export type DsarArticle = "15" | "15+20";

export interface DsarTableSpec {
  /**
   * The column on the table whose value equals the data subject's
   * `auth.users.id`. For `users`, this is `id` (self-reference). For
   * `audit_byok_use`, the owner column is named `founder_id`. For
   * `messages` and `message_attachments` there is NO direct owner
   * column — the worker joins via `joinVia`.
   */
  ownerField: string;
  /**
   * GDPR article(s) under which the rows are exported. `15` is the
   * right-of-access baseline; `15+20` adds portability (machine-
   * readable + reusable) which applies to data the subject themselves
   * provided. Audit rows are 15-only (not user-provided).
   */
  article: DsarArticle;
  /**
   * For tables with no direct user_id column, the join chain that
   * reaches `auth.users.id`. The worker handles each `joinVia` table
   * by constructing a nested query through the parent table.
   */
  joinVia?: {
    parentTable: string;
    parentJoinColumn: string; // FK column on the child pointing at parent.id
  };
}

export const DSAR_TABLE_ALLOWLIST: Readonly<Record<string, DsarTableSpec>> = {
  // Account profile (Art. 15: identification data).
  users: { ownerField: "id", article: "15" },

  // BYOK encrypted credentials (Art. 15: encrypted ciphertext returned
  // base64-encoded; the user provided the underlying key, hence 15+20).
  api_keys: { ownerField: "user_id", article: "15+20" },

  // Conversations the user initiated (Art. 15+20: user-provided).
  conversations: { ownerField: "user_id", article: "15+20" },

  // Per-conversation messages — joined via conversation_id.
  messages: {
    ownerField: "user_id",
    article: "15+20",
    joinVia: {
      parentTable: "conversations",
      parentJoinColumn: "conversation_id",
    },
  },

  // Per-message attachments — joined via message_id -> messages ->
  // conversations.user_id. The worker materialises the nested join
  // server-side via service-role + assertReadScope on the resolved
  // conversation owner.
  message_attachments: {
    ownerField: "user_id",
    article: "15+20",
    joinVia: {
      parentTable: "messages",
      parentJoinColumn: "message_id",
    },
  },

  // Knowledge-base share links the user created (Art. 15+20).
  kb_share_links: { ownerField: "user_id", article: "15+20" },

  // Team/agent display names the user customised (Art. 15+20).
  team_names: { ownerField: "user_id", article: "15+20" },

  // BYOK usage audit — Art. 15 (controller-collected, not user-
  // provided). Note non-standard owner column name.
  audit_byok_use: { ownerField: "founder_id", article: "15" },

  // T&C consent ledger (migration 044, feat-oauth-tc-consent-3205).
  // Art. 15: the user has the right to know which T&C versions they
  // accepted (with timestamp + document fingerprint). The row is the
  // user's own consent record — they provided it (by clicking
  // accept), so 15+20 also applies. The WORM trigger + Art. 17
  // anonymise RPC handle erasure separately.
  tc_acceptances: { ownerField: "user_id", article: "15+20" },

  // Per-action-class scope grants (migration 048, PR-G #3947).
  // Art. 15+20: the user explicitly authorised each action class at a
  // chosen tier (`auto` / `draft_one_click` / `approve_every_time`).
  // The grant ledger is the user-provided consent record under Art. 7
  // — they have the right to export the timestamped chain. The WORM
  // trigger + anonymise_scope_grants RPC handle erasure separately.
  scope_grants: { ownerField: "founder_id", article: "15+20" },

  // GitHub App installation-token use audit (migration 052, PR-H #3244).
  // Art. 15: controller-collected, not user-provided. RLS owner-select
  // already exposes these rows to the founder via the dashboard; the
  // DSAR bundle exports them under the same Art. 15 framing as
  // audit_byok_use (note non-standard owner column name).
  audit_github_token_use: { ownerField: "founder_id", article: "15" },

  // Per-send action signature ledger (migration 051, PR-H #4077).
  // Art. 15: the user has the right to know which sends the platform
  // recorded under their authorization. Body and recipient are stored
  // as SHA-256 hashes only (raw values never persisted), but the user
  // still has access to: which action_class was invoked, which tier
  // was active at the click (`tier_at_send`), when (`clicked_at`),
  // whether the typed-confirm gate was satisfied (`confirmed_typed`),
  // the cryptographic signature (`approval_signature_sha256`), and
  // which grant was active (`grant_id`). Marked 15-only because the
  // founder did not "provide" the signature row — it is platform-
  // generated evidence of their click, analogous to an audit row.
  // The WORM trigger + anonymise_action_sends RPC handle erasure
  // separately (Art. 17 cascade in server/account-delete.ts).
  action_sends: { ownerField: "user_id", article: "15" },

  // Per-template authorization ledger (migration 053, PR-I #4078).
  // Art. 15+20: the founder explicitly authorised each template via the
  // first-send-IS-authorization pattern — the Send click on a labeled
  // draft_one_click button IS the Art. 7(3) "specific" + "informed"
  // consent act. The ledger captures (template_hash, action_class,
  // authorized_at, expires_at, soft_reconfirm_at, max_sends, revoked_at,
  // revocation_reason, grant_id). Pure-template-hash + bounds are user-
  // generated context (15+20 portability applies). Founder-readable
  // via /dashboard/settings/scope-grants. WORM trigger + anonymise_
  // template_authorizations RPC handle erasure separately (Art. 17
  // cascade in account-delete.ts between anonymise_action_sends and
  // anonymise_scope_grants).
  template_authorizations: { ownerField: "founder_id", article: "15+20" },

  // feat-team-workspace-multi-user (migration 053) — organizations the
  // user owns. ownerField = owner_user_id (direct). Art. 15 only:
  // backfill-shaped solo organizations have name=NULL; the user did not
  // "provide" the row, the trigger created it on signup. Post-flag-flip
  // orgs created by an explicit invite-flow may carry user-provided name
  // — they remain Art. 15 (the entity-of-record) rather than Art. 20
  // because the value identifies the corporate context, not the user.
  organizations: { ownerField: "owner_user_id", article: "15" },

  // feat-team-workspace-multi-user (migration 053) — workspaces the user
  // is a member of. No direct user_id column — joined via
  // workspace_members.workspace_id. Art. 15: workspace metadata (name)
  // identifies the shared context but is not user-provided content.
  workspaces: {
    ownerField: "user_id",
    article: "15",
    joinVia: {
      parentTable: "workspace_members",
      parentJoinColumn: "id", // workspaces.id matches workspace_members.workspace_id
    },
  },

  // feat-team-workspace-multi-user (migration 053) — every workspace
  // membership row the user holds. ownerField = user_id (direct). Art.
  // 15+20: by accepting an invite (or owning the workspace at signup)
  // the user provided the membership relation; they retain portability.
  workspace_members: { ownerField: "user_id", article: "15+20" },

  // feat-team-workspace-multi-user (migration 058) — invite consent
  // attestations the user accepted. ownerField = invitee_user_id (the
  // primary owner column tracked here for allowlist-completeness lint).
  // The export pipeline at dsar-export.ts uses a `.or()` filter on BOTH
  // invitee_user_id AND inviter_user_id so a departed member's INVITER-
  // side rows are recovered too (Kieran P1-1 / #4230). assertReadScope
  // there is two-arm-aware (validates EITHER column matches). Art. 15:
  // WORM consent record, analogous to tc_acceptances. The Art. 17
  // anonymise RPC handles erasure separately.
  workspace_member_attestations: {
    ownerField: "invitee_user_id",
    article: "15",
  },

  // feat-dsar-departed-member-coverage (migration 062, #4230) — WORM
  // ledger of workspace-member removal events. ownerField =
  // removed_user_id; rows describe (workspace_id, removed_user_id,
  // removed_by_user_id, removed_at). The actor (removed_by_user_id) is
  // co-member audit metadata — when the actor files their own DSAR they
  // see the removals they performed via the
  // anonymise_workspace_member_removals Art. 17 cascade NULLing both
  // PII columns. Art. 15 only: the user did not "provide" this row, the
  // remove_workspace_member RPC wrote it on the actor's click.
  // 36-month retention deviates from 24-mo PA-PII envelope; rationale
  // in ADR-039.
  workspace_member_removals: {
    ownerField: "removed_user_id",
    article: "15",
  },
};

/**
 * Tables explicitly excluded from the DSAR bundle, each with a
 * documented reason that survives review and audits. AC28 + S6 require
 * a reason per excluded table — empty string is rejected by the lint.
 */
export const DSAR_TABLE_EXCLUSIONS: Readonly<Record<string, string>> = {
  // DSAR meta — including would be recursive (a bundle containing
  // metadata about prior bundles' issuance). PII is in
  // dsar_export_audit_pii which is handled by the Art. 17 cascade,
  // not by the Art. 15 export.
  dsar_export_jobs:
    "DSAR meta about the export itself; including would be recursive. " +
    "Art. 17 cascade anonymises this row's PII separately.",
  dsar_export_audit_pii:
    "PII-segregated audit; subject to Art. 17 anonymisation cascade " +
    "(account-delete.ts), not Art. 15 export. The user-readable jobs " +
    "row in dsar_export_jobs already covers their own request history.",

  // Operational state (no personal data).
  user_concurrency_slots:
    "Operational concurrency-slot bookkeeping. Transient runtime state, " +
    "not personal data. Cleared on session end.",
  push_subscriptions:
    "Web Push endpoint tokens — device-specific, transient, " +
    "auto-deleted on 410 Gone. Per spec FR8 not enumerated as Art. 15 " +
    "personal data. The user can revoke via browser permissions.",
  denied_jti:
    "Runtime-JWT revocation list (security telemetry). The jti is a " +
    "random-ID per token, not user-provided content; rows index a " +
    "user only as a side-effect of the mint event. Per spec FR8 not " +
    "enumerated as Art. 15 personal data.",
  mint_rate_window:
    "Per-founder JWT-mint rate-limit counter (security telemetry). " +
    "Rolling 60/hour bucket; no user-provided content. Per spec FR8 " +
    "not enumerated as Art. 15 personal data.",
  runtime_mint_intent:
    "Runtime-JWT mint marker (Phase-4 hook discriminator, ADR-033 §0.7). " +
    "≤10-second lifetime row written by tenant.ts before generateLink " +
    "and atomically DELETEd by the Custom Access Token Hook. " +
    "Ephemeral by design — no row survives past the mint flow. ON DELETE " +
    "CASCADE from auth.users handles any edge-case orphan on user delete. " +
    "No user-provided content; user_id is the only column and is already " +
    "in the DSAR's auth.users export. Per spec FR8 not enumerated as " +
    "Art. 15 personal data.",
  // feat-team-workspace-multi-user — `user_session_state` remains
  // excluded after Phase 7 promotion of organizations + workspaces +
  // workspace_members + workspace_member_attestations. The single row's
  // `current_organization_id` is duplicated into the JWT custom claim
  // `app_metadata.current_organization_id` which is already part of the
  // auth.users export. No user-provided content; transient UX
  // preference. ON DELETE CASCADE from auth.users handles Art. 17.
  user_session_state:
    "Per-user UX preference (current_organization_id) duplicated in JWT " +
    "custom claim app_metadata.current_organization_id which is already " +
    "part of the auth.users export. No user-provided content. ON DELETE " +
    "CASCADE from auth.users handles Art. 17 erasure.",

  tenant_deploy_audit:
    "Multi-tenant deploy substrate orchestration-plane meta-audit log " +
    "(migration 043, ADR-030, plan #3723). v1 single-tenant scope " +
    "(Soleur-as-tenant-zero only): the controller and data subject for " +
    "any rows that exist are the same legal entity (Jikigai's operator). " +
    "Substrate is explicitly scope-outed for end-user disclosure at v1 " +
    "per compliance-posture.md Active Items row #3723 — the re-" +
    "evaluation trigger is first non-Soleur tenant onboarding, at which " +
    "point this row moves to DSAR_TABLE_ALLOWLIST (founder_id, Art. 15) " +
    "and Privacy Policy §4.7 + GDPR Policy §6.1.b + DPD §2.3 are " +
    "updated in lockstep via the legal-doc cross-document gate. Until " +
    "then, no non-Soleur founder data subject exists for whom Art. 15 " +
    "export of this table would be non-empty. Art. 17 anonymise is " +
    "handled separately via the `anonymise_tenant_deploy_audit` RPC " +
    "called BEFORE `auth.admin.deleteUser()` per the ON DELETE " +
    "RESTRICT FK ordering.",
};

/**
 * Test helper: union of every table the worker is aware of. Used by
 * the file-parse lint to assert the migration discovery set is
 * partitioned by allowlist + exclusions with no leftover.
 */
export const DSAR_TABLES_KNOWN: ReadonlySet<string> = new Set([
  ...Object.keys(DSAR_TABLE_ALLOWLIST),
  ...Object.keys(DSAR_TABLE_EXCLUSIONS),
]);
