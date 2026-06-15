// Cold-outbound email compliance chokepoint (#5325, pilot slice).
//
// sendCompliantOutbound() is the ONLY path that sends cold outreach, the ONLY
// module that holds the outbound.soleur.ai FROM literal, and the ONLY non-
// transactional caller of resend.emails.send (enforced by the sentinel in
// test/server/outbound-chokepoint.test.ts). Every gate is refuse-to-send (throws
// before Resend); the order is load-bearing — validate → domain-verified →
// body-hash match → in-txn suppression recheck → Resend → record WORM audit.
//
// Approval model (ADR-060): the gated-tier review is the human trust boundary.
// The caller passes approvedBodySha256 (the hash of the body the human approved
// at the gate); the chokepoint recomputes sha256(body) and rejects on mismatch,
// so a body mutated after approval cannot be sent. The send is recorded into the
// outbound_sends WORM table (migration 104) via record_outbound_send.

import { createHash } from "node:crypto";

import { getResend } from "@/server/notifications";
import { reportSilentFallback } from "@/server/observability";
import {
  OutboundComplianceError,
  validateComplianceConditions,
  validateEmailHeaders,
  assertRecipientAllowed,
  recipientHash,
  type Jurisdiction,
  type Art14Disclosure,
} from "@/server/email-triage/outbound-compliance";

// Typed FROM discriminant for the cold sending subdomain. This module is the
// ONLY place the outbound.soleur.ai literal appears; transactional senders
// (notifications.ts, cron-email-ingress-probe.ts) send from the soleur.ai apex
// (notifications@soleur.ai) and structurally cannot reach this value. The
// dedicated outbound.soleur.ai subdomain isolates cold-outreach sender reputation
// from the product's transactional mail (separate DKIM/DMARC stream).
export type FromDomain = "outbound.soleur.ai";
export const OUTBOUND_FROM = "Soleur <hello@outbound.soleur.ai>";

function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

// Narrow structural client — the chokepoint only needs `.rpc`. A real
// SupabaseClient satisfies this; tests pass a minimal mock.
export interface OutboundSupabase {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message?: string | null } | null }>;
}

export interface SendCompliantOutboundArgs {
  supabase: OutboundSupabase;
  /** auth.uid() of the founder on whose behalf the send is made. */
  ownerId: string;
  /** Plaintext recipient. For email_reply this is resolved server-side from the
   *  inbound message_id by the tool layer, never from agent args (P0-3). */
  to: string;
  subject: string;
  bodyText: string;
  replyTo?: string;
  jurisdiction: Jurisdiction;
  postalAddress?: string;
  optOut?: string;
  art14?: Art14Disclosure;
  ftcDisclosure?: string;
  /** The body hash the human approved at the gated review (P0-1 body-binding). */
  approvedBodySha256: string;
}

function assertSendingDomainVerified(): void {
  if (process.env.OUTBOUND_SENDING_DOMAIN_VERIFIED !== "true") {
    throw new OutboundComplianceError(
      "domain_unverified",
      "outbound.soleur.ai sending domain is not verified " +
        "(OUTBOUND_SENDING_DOMAIN_VERIFIED != 'true') — refusing to send until " +
        "Resend reports the domain verified (deepen P1).",
    );
  }
}

export async function sendCompliantOutbound(
  args: SendCompliantOutboundArgs,
): Promise<{ resendId: string; outboundSendId: string }> {
  const {
    supabase,
    ownerId,
    to,
    subject,
    bodyText,
    replyTo,
    jurisdiction,
    postalAddress,
    optOut,
    art14,
    ftcDisclosure,
    approvedBodySha256,
  } = args;

  // 1. Domain-verified precondition (deepen P1) — before any other work.
  assertSendingDomainVerified();

  // 2. Compliance C1–C4 + C3 Art.14 (default-to-EU/UK-strict on unknown).
  validateComplianceConditions({
    to,
    from: OUTBOUND_FROM,
    subject,
    bodyText,
    replyTo,
    jurisdiction,
    postalAddress,
    optOut,
    art14,
    ftcDisclosure,
  });

  // 3. RFC-5322 header-injection guard (dedicated, not the display sanitizer).
  validateEmailHeaders({ to, from: OUTBOUND_FROM, subject, replyTo });

  // 4. Recipient allow-list — no internal/own-domain/role addresses (P0-3).
  assertRecipientAllowed(to);

  // 5. Body-hash approval match (P0-1) — reject a body mutated after approval.
  const perSendBodySha256 = sha256(bodyText);
  if (perSendBodySha256 !== approvedBodySha256) {
    throw new OutboundComplianceError(
      "approval_body_mismatch",
      "Body hash does not match the approved hash — the body was mutated after approval.",
    );
  }

  // 6. In-txn suppression recheck (C5, deepen P1) — immediately before send.
  //    Suppression is monotonic (false→true only), so this closes most of the
  //    check-then-send TOCTOU; a late add can only over-suppress, never under.
  const rHash = recipientHash(to);
  const { data: suppressed, error: supErr } = await supabase.rpc(
    "is_recipient_suppressed",
    { p_recipient_hash: rHash },
  );
  if (supErr) {
    reportSilentFallback(supErr, {
      feature: "outbound-email",
      op: "outbound.suppression_check",
      extra: { userId: ownerId },
      message: "is_recipient_suppressed RPC failed — refusing to send",
    });
    throw new OutboundComplianceError(
      "suppression_check_failed",
      "Suppression recheck failed — refusing to send.",
    );
  }
  if (suppressed === true) {
    throw new OutboundComplianceError(
      "recipient_suppressed",
      "Recipient is on the suppression list — refusing to send (C5).",
    );
  }

  // 6b. Duplicate-send guard (user-impact review) — refuse if this exact
  //     approved body has already been sent to this recipient. Prevents the
  //     "duplicate cold email to a journalist" failure on a tool retry. The
  //     UNIQUE(owner_id, recipient_hash, approved_body_sha256) index closes the
  //     concurrent-race residual this SELECT cannot.
  const { data: alreadySent, error: dupErr } = await supabase.rpc(
    "outbound_send_exists",
    { p_recipient_hash: rHash, p_approved_body_sha256: approvedBodySha256 },
  );
  if (dupErr) {
    reportSilentFallback(dupErr, {
      feature: "outbound-email",
      op: "outbound.dedup_check",
      extra: { userId: ownerId },
      message: "outbound_send_exists RPC failed — refusing to send",
    });
    throw new OutboundComplianceError(
      "dedup_check_failed",
      "Duplicate-send check failed — refusing to send.",
    );
  }
  if (alreadySent === true) {
    throw new OutboundComplianceError(
      "duplicate_send",
      "This exact approved body has already been sent to this recipient — refusing to re-send.",
    );
  }

  // 7. Resend dispatch — the un-rollback-able side effect. PII (recipient/body)
  //    must NEVER reach Sentry: a raw Resend error can echo the recipient, so
  //    the mirror carries only op + hashed userId, never the error payload's
  //    address. We pass a synthetic Error, not the raw vendor error object.
  const { data: sent, error: sendErr } = await getResend().emails.send({
    from: OUTBOUND_FROM,
    to: [to],
    subject,
    text: bodyText,
    ...(replyTo ? { replyTo } : {}),
  });
  if (sendErr || !sent?.id) {
    reportSilentFallback(new Error("outbound.send_error"), {
      feature: "outbound-email",
      op: "outbound.send_error",
      extra: { userId: ownerId },
      message: "Resend send failed for an outbound cold email",
    });
    throw new OutboundComplianceError("send_error", "Resend send failed.");
  }
  const resendId = sent.id;

  // 8. Record the WORM audit row (after the send succeeded). A failure here is
  //    an audit gap (the mail already went out) — surface loudly.
  const { data: recId, error: recErr } = await supabase.rpc(
    "record_outbound_send",
    {
      p_recipient_hash: rHash,
      p_approved_body_sha256: approvedBodySha256,
      p_per_send_body_sha256: perSendBodySha256,
      p_resend_id: resendId,
    },
  );
  if (recErr || typeof recId !== "string") {
    reportSilentFallback(recErr ?? new Error("record_outbound_send returned no id"), {
      feature: "outbound-email",
      op: "outbound.record_error",
      extra: { userId: ownerId, resendId },
      message:
        "record_outbound_send failed AFTER a successful Resend dispatch (audit gap)",
    });
    throw new OutboundComplianceError(
      "record_error",
      "Send dispatched but the audit record failed — investigate (audit gap).",
    );
  }

  return { resendId, outboundSendId: recId };
}
