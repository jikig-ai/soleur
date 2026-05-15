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
