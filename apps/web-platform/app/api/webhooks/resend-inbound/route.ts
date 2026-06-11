// #5103 Phase 3 — Resend Inbound webhook ingress (3rd multi-source ingress
// after Stripe and the GitHub App). Order of operations mirrors the
// canonical `app/api/webhooks/github/route.ts` — the ordering is
// load-bearing:
//
//   Step 0: bounded body read → 413 BEFORE anything else (we cannot verify
//           a body we refused to read in full).
//   Step 1: RESEND_INBOUND_WEBHOOK_SECRET unset → 500 + Sentry BEFORE
//           touching svix. svix's Webhook constructor throws on an empty
//           secret ("Secret can't be empty.") — without this explicit
//           guard a misconfiguration is indistinguishable from a
//           signature failure (github/route.ts:107-118 idiom, never
//           Stripe's `!` assertion).
//   Step 2: svix signature verify on the RAW body (`await req.text()`
//           before any parse — svix HMACs the exact bytes). verify()
//           THROWS on failure, it does not return a boolean → 401.
//   Step 3: JSON.parse BEFORE the dedup insert — malformed JSON → 400
//           with nothing claimed, nothing to release.
//   Step 4: event-type gate, then plain-insert dedup into
//           processed_resend_events via lib/webhook-dedup (23505-catch
//           idiom — supabase-js data:null quirk, mig 052 comment).
//   Step 5: three-way release classification after a successful claim:
//           (1) transient failure (inngest.send) → release + 500 (the
//               svix retry is wanted);
//           (2) deterministically unprocessable (missing data.email_id)
//               → KEEP the row + 200 + Sentry warn — a svix retry is
//               byte-identical; release+500 is a 10-hour poison-retry
//               storm (github/route.ts:216-219 rationale);
//           (3) malformed JSON never claimed (step 3) → plain 400.
//
// Verify-implementation choice: svix's `Webhook` class directly, NOT
// `new Resend(...).webhooks.verify(...)`. The Resend constructor throws
// without an API key (resend@6.12.3 dist/index.mjs — "Missing API key"),
// which would couple signature verification to RESEND_API_KEY; resend's
// own verify() is a one-line delegation to this exact svix call. svix is
// pinned exactly ("svix": "1.92.2") by resend's own dependency set.
//
// PII discipline (TR3 tri-ban): no body, sender, or subject values in any
// log call, Sentry tag/extra/message, or Error string — op-tags and the
// svix delivery id only.

import { NextResponse } from "next/server";
import { Webhook } from "svix";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";
import { createServiceClient } from "@/lib/supabase/server";
import { claimDelivery, releaseDelivery } from "@/lib/webhook-dedup";
import { sendInngestWithRetry } from "@/server/inngest/send-with-retry";
import {
  EMAIL_INBOUND_RECEIVED_EVENT,
  type EmailInboundReceivedData,
} from "@/server/email-triage/events";

const FEATURE = "resend-inbound-webhook";
const DEDUP_TABLE = "processed_resend_events";
const DEDUP_COLUMN = "svix_id";

// 256 KiB — generous for a metadata-only payload (Resend's email.received
// carries attachment METADATA, never content). DoS guard rail, not a
// feature limit: if a legitimate payload ever trips this, raise the cap
// explicitly rather than silently truncating (github/route.ts:62-69).
const MAX_WEBHOOK_BODY_BYTES = 262_144;

function readWebhookSecret(): string | null {
  const v = process.env.RESEND_INBOUND_WEBHOOK_SECRET;
  return v && v.length > 0 ? v : null;
}

interface ResendInboundBody {
  type?: unknown;
  data?: {
    email_id?: unknown;
    created_at?: unknown;
    from?: unknown;
    message_id?: unknown;
    subject?: unknown;
    attachments?: unknown;
  };
}

export async function POST(request: Request) {
  // Step 0: bounded read. Content-Length is advisory — guard the actual
  // byte length AFTER .text() resolves. 413 before any other work.
  const rawBody = await request.text();
  if (rawBody.length > MAX_WEBHOOK_BODY_BYTES) {
    return NextResponse.json({ error: "Payload too large" }, { status: 413 });
  }

  // Step 1: fail-closed secret guard BEFORE svix is touched.
  const secret = readWebhookSecret();
  if (!secret) {
    logger.error(
      { feature: FEATURE },
      "RESEND_INBOUND_WEBHOOK_SECRET unset — fail-closed 500",
    );
    Sentry.captureMessage("Resend inbound webhook secret unset", {
      level: "error",
      tags: { feature: FEATURE, op: "secret" },
    });
    return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
  }

  // Step 2: svix signature verification over the raw body.
  const svixId = request.headers.get("svix-id");
  const svixTimestamp = request.headers.get("svix-timestamp");
  const svixSignature = request.headers.get("svix-signature");
  if (!svixId || !svixTimestamp || !svixSignature) {
    logger.error(
      { feature: FEATURE, svixId },
      "Resend inbound webhook: missing svix-* header(s) — 401",
    );
    return NextResponse.json({ error: "Missing svix headers" }, { status: 401 });
  }

  // Steps 2+3 fused: standardwebhooks' verify() ends in
  // `JSON.parse(payload)` AFTER the timing-safe HMAC match (hard ±5-min
  // replay tolerance), so verification and parsing are one call and the
  // thrown error type discriminates the two failure classes:
  //   - WebhookVerificationError → signature/timestamp failure → 401;
  //   - SyntaxError → signature MATCHED but the body is not valid JSON →
  //     400. This happens BEFORE the dedup insert — nothing has been
  //     claimed, so there is nothing to release (github/route.ts parses
  //     after its insert and must release; pre-claim parse is strictly
  //     simpler for the same outcome).
  let body: ResendInboundBody;
  try {
    body = new Webhook(secret).verify(rawBody, {
      "svix-id": svixId,
      "svix-timestamp": svixTimestamp,
      "svix-signature": svixSignature,
    }) as ResendInboundBody;
  } catch (err) {
    if (err instanceof SyntaxError) {
      logger.error(
        { feature: FEATURE, svixId },
        "Resend inbound webhook: body is not valid JSON",
      );
      return NextResponse.json({ error: "Malformed body" }, { status: 400 });
    }
    // WebhookVerificationError — or anything else: fail closed as 401.
    logger.error(
      { feature: FEATURE, svixId },
      "Resend inbound webhook: signature verification failed",
    );
    Sentry.captureMessage("Resend inbound webhook signature verification failed", {
      level: "error",
      tags: { feature: FEATURE, op: "signature" },
      extra: { svixId },
    });
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }

  // Step 4a: event-type gate. No dedup insert needed for non-received
  // types: we never process them, so a redelivery of one costs nothing —
  // dedup exists to stop double-PROCESSING, and there is no processing
  // here to double.
  if (body?.type !== "email.received") {
    logger.info(
      { feature: FEATURE, svixId },
      "Resend inbound webhook: non-received event type — ignoring",
    );
    return NextResponse.json({ received: true });
  }

  // Step 4b: dedup claim (plain insert + 23505 catch — see module header).
  const supabase = createServiceClient();
  const claim = await claimDelivery(supabase, DEDUP_TABLE, DEDUP_COLUMN, svixId);
  if (claim.error) {
    logger.error(
      { err: claim.error, feature: FEATURE, svixId },
      "Resend inbound webhook: dedup insert failed — returning 500",
    );
    Sentry.captureException(claim.error, {
      tags: { feature: FEATURE, op: "dedup-insert" },
      extra: { svixId },
    });
    return NextResponse.json({ error: "DB error" }, { status: 500 });
  }
  if (!claim.claimed) {
    logger.info(
      { feature: FEATURE, svixId },
      "Resend inbound webhook: replay — svix_id already processed, skipping",
    );
    return NextResponse.json({ received: true, duplicate: true });
  }

  // Step 5 case (2): deterministically unprocessable. KEEP the dedup row —
  // a svix retry carries byte-identical content; releasing + 500 here
  // would be a 10-hour poison-retry storm (github/route.ts:216-219).
  const data = body.data;
  const resendEmailId = data?.email_id;
  if (typeof resendEmailId !== "string" || resendEmailId.length === 0) {
    logger.warn(
      { feature: FEATURE, svixId },
      "Resend inbound webhook: no data.email_id in payload — dropping (dedup row kept)",
    );
    Sentry.captureMessage("Resend inbound webhook payload missing email_id", {
      level: "warning",
      tags: { feature: FEATURE, op: "unprocessable" },
      extra: { svixId },
    });
    return NextResponse.json({ received: true });
  }

  // receivedAt: the RECEIVE timestamp from the payload, passed through
  // verbatim — never `now()` at processing time (a 10-hour webhook retry
  // must not eat an Art. 12 clock, and the WORM trigger freezes the value
  // forever). Missing/unparseable → svix-timestamp envelope fallback
  // (unix seconds; svix verification already validated it) + provenance
  // marker + Sentry warn.
  const createdAtRaw = data?.created_at;
  let receivedAt: string;
  let receivedAtSource: EmailInboundReceivedData["receivedAtSource"];
  if (
    typeof createdAtRaw === "string" &&
    !Number.isNaN(Date.parse(createdAtRaw))
  ) {
    receivedAt = createdAtRaw;
    receivedAtSource = "payload";
  } else {
    receivedAt = new Date(Number(svixTimestamp) * 1000).toISOString();
    receivedAtSource = "envelope";
    logger.warn(
      { feature: FEATURE, svixId },
      "Resend inbound webhook: data.created_at missing/unparseable — svix-timestamp envelope fallback",
    );
    Sentry.captureMessage(
      "Resend inbound webhook: received_at fell back to envelope timestamp",
      {
        level: "warning",
        tags: { feature: FEATURE, op: "received-at-fallback" },
        extra: { svixId },
      },
    );
  }

  // Attachment METADATA only — never content, never download URLs.
  const attachmentsRaw = data?.attachments;
  const attachments = Array.isArray(attachmentsRaw)
    ? attachmentsRaw.map((a: { filename?: unknown; content_type?: unknown }) => ({
        filename: typeof a?.filename === "string" ? a.filename : "",
        contentType: typeof a?.content_type === "string" ? a.content_type : "",
      }))
    : [];

  const eventData: EmailInboundReceivedData = {
    v: "1",
    svixId,
    resendEmailId,
    messageId: typeof data?.message_id === "string" ? data.message_id : null,
    sender: typeof data?.from === "string" ? data.from : "",
    subject: typeof data?.subject === "string" ? data.subject : "",
    receivedAt,
    receivedAtSource,
    attachments,
  };

  // Step 5 case (1) + dispatch. Single event-id namespace per delivery —
  // the Inngest 24h event.id dedup window + our DB dedup combine to give
  // exactly-once dispatch up to svix's retry limit. On failure the dedup
  // row MUST be released so the svix retry is processed, not swallowed as
  // a duplicate.
  try {
    const { inngest } = await import("@/server/inngest/client");
    await sendInngestWithRetry(
      () =>
        inngest.send({
          id: `resend-${svixId}`,
          name: EMAIL_INBOUND_RECEIVED_EVENT,
          v: "1",
          data: eventData,
        }),
      { feature: FEATURE, deliveryId: svixId },
    );
  } catch (err) {
    logger.error(
      { err, feature: FEATURE, svixId },
      "Resend inbound webhook: inngest.send failed — releasing dedup row",
    );
    Sentry.captureException(err, {
      tags: { feature: FEATURE, op: "inngest-send" },
      extra: { svixId },
    });
    await releaseDelivery(supabase, DEDUP_TABLE, DEDUP_COLUMN, svixId);
    return NextResponse.json({ error: "Dispatch failed" }, { status: 500 });
  }

  return NextResponse.json({ received: true });
}
