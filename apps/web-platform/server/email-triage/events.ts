// #5103 Phase 3 — shared constants for the operator-inbox-delegation
// feature. Client-free module (no supabase/inngest imports) so the webhook
// route, the Inngest pipeline, and test files share one source of truth —
// the WORKSPACE_RECONCILE_REQUESTED_EVENT pattern (server/session-sync.ts).
//
// Event name is `email/inbound.received` — NOT `email/received`, which
// would collide with Resend's own outbound `email.*` webhook taxonomy.
export const EMAIL_INBOUND_RECEIVED_EVENT = "email/inbound.received";

export interface EmailInboundReceivedData {
  v: "1";
  /** svix-id header — the delivery id, also the dedup key. */
  svixId: string;
  /** Resend webhook `data.email_id` — key for GET /emails/receiving/{id}. */
  resendEmailId: string;
  /** RFC 5322 Message-ID (`data.message_id`) — optional per the RFC. */
  messageId: string | null;
  /** `data.from`. Unauthenticated claim — Sieve forwarding strips SPF/DKIM
   * context; no consumer may derive trust from it. */
  sender: string | null; // nullable: missing/empty From header → null (NULL-not-empty-string discipline, mig 102)
  subject: string;
  /** `data.created_at` — the RECEIVE timestamp, never route-processing
   * time. A 10-hour webhook retry must not eat an Art. 12 clock. */
  receivedAt: string;
  /** "envelope" when `data.created_at` was missing/unparseable and the
   * svix-timestamp header (unix seconds → ISO) was used instead — recorded
   * as provenance + Sentry warn at the route. */
  receivedAtSource: "payload" | "envelope";
  /** Attachment metadata ONLY — never content, never download URLs. */
  attachments: { filename: string; contentType: string }[];
}
