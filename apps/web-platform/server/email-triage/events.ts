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
  /** Normalized, deduped, sorted recipient addresses (`data.to` +
   * `data.received_for`) — the routing key for `email_inbox_routes`
   * (ADR-269). NORMALIZED addresses only: no display names, no mixed case,
   * because this field lands in the Inngest event store. Optional: events
   * dispatched before the field existed carry none, and an absent/empty list
   * means "no routing" (env-owner path). */
  recipients?: string[];
}

/** Cap on VALID recipient addresses kept per inbound mail (the routes lookup
 * is `.in("address", recipients)`, so this also bounds the request URL). Mail
 * addressed to more recipients than this is not a routing case. */
export const MAX_INBOUND_RECIPIENTS = 20;

const MAX_ADDRESS_LENGTH = 320;
// The one strict validator. The `email_inbox_routes.address` CHECK is
// deliberately loose (shape only): a stored address the strict rules would
// reject simply never matches an event (fail-closed to the env owner), so the
// two cannot drift into a misroute and a change to the address rules is a
// one-place edit, here.
const ADDRESS_RE = /^[a-z0-9._%+-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}$/;

/**
 * Normalize one recipient to its routing-key form: `addr` or `Name <addr>`,
 * trimmed and lowercased. Returns null for anything that is not a plausible
 * address (including non-strings and values over 320 characters).
 */
export function normalizeInboundAddress(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  let s = raw.trim();
  const angle = s.match(/<([^<>]*)>\s*$/);
  if (angle) s = angle[1].trim();
  s = s.toLowerCase();
  if (s.length === 0 || s.length > MAX_ADDRESS_LENGTH) return null;
  return ADDRESS_RE.test(s) ? s : null;
}

/**
 * Build the event's `recipients` from the webhook's address fields. Pass the
 * ENVELOPE field first (`received_for`) and the sender-written header (`to`)
 * second. Keeps at most MAX_INBOUND_RECIPIENTS VALID addresses (first-N in
 * source order), examining at most 4x that many raw entries so a hostile list
 * cannot make this loop long. Deduped and sorted so the result is deterministic.
 */
export function buildRecipients(...sources: unknown[]): string[] {
  const found = new Set<string>();
  let examined = 0;
  for (const source of sources) {
    if (!Array.isArray(source)) continue;
    for (const entry of source) {
      if (
        found.size >= MAX_INBOUND_RECIPIENTS ||
        examined >= MAX_INBOUND_RECIPIENTS * 4
      ) {
        return [...found].sort();
      }
      examined += 1;
      const addr = normalizeInboundAddress(entry);
      if (addr !== null) found.add(addr);
    }
  }
  return [...found].sort();
}
