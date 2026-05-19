// PR-H (#4077) — POST /api/dashboard/today/[id]/send
//
// Founder-callable: completes a draft by re-checking the active scope_grant
// at click-time, writing the action_sends signature row, and flipping the
// message to archived. Branches on grant.tier:
//
//   - draft_one_click       → straight through; write action_sends + archive
//   - approve_every_time    → require confirmed_typed=true && typed_value="SEND"
//                              in the request body; else 409 requires_confirmation
//   - auto / auto_with_digest → 400 (these are not founder-initiated paths)
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports + dynamic.
// reportSilentFallback wraps 4 distinct error surfaces; will migrate to
// reportSilentFallbackWithUser when #3739 ships.

import { NextResponse } from "next/server";
import { createHash } from "node:crypto";
import * as Sentry from "@sentry/nextjs";

import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isGranted } from "@/server/scope-grants/is-granted";
import {
  isKnownActionClass,
  type ActionClass,
} from "@/server/scope-grants/action-class-map";
import { writeActionSend } from "@/server/action-sends/write-action-send";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

interface SendBody {
  confirmed_typed?: unknown;
  typed_value?: unknown;
  recipient_identifier?: unknown;
  body_content?: unknown;
}

function templateHashFor(message: {
  action_class: ActionClass;
  owning_domain: string | null;
}, tier: string): string {
  // PR-H template hash: stable across (action_class, owning_domain, tier)
  // triple. PR-I will replace this with a real template_authorizations
  // record once template-bound E&O windows ship.
  return createHash("sha256")
    .update(`${message.action_class}:${message.owning_domain ?? ""}:${tier}`)
    .digest("hex");
}

export async function POST(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/today/[id]/send", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { id: messageId } = await params;

  let body: SendBody = {};
  try {
    body = (await req.json()) as SendBody;
  } catch {
    // Empty body is OK for draft_one_click; only approve_every_time
    // requires the confirmation payload.
    body = {};
  }

  // Per Kieran P1-3 + Phase 4.3: cookie-scoped client used for messages
  // SELECT (RLS owner-only) AND for isGranted re-check (scope_grants
  // owner-select RLS lets the founder self-read). Service-role NOT used.
  const { data: message, error: msgErr } = await supabase
    .from("messages")
    .select("id, user_id, action_class, status, draft_preview, owning_domain")
    .eq("id", messageId)
    .eq("user_id", user.id) // belt-and-suspenders alongside RLS
    .maybeSingle();

  if (msgErr) {
    reportSilentFallback(msgErr, {
      feature: "dashboard-send",
      op: "messages-select",
      message: "Failed to load message for send",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!message) {
    // Either no row, or cross-tenant request. Treat both as 403 (do not
    // distinguish — distinguishing leaks the existence of an id).
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }
  if (message.status !== "draft") {
    return NextResponse.json(
      { error: "not_a_draft", status: message.status },
      { status: 409 },
    );
  }
  if (!isKnownActionClass(message.action_class as string)) {
    // Backfill at mig 051 should have covered this; defensive 422.
    return NextResponse.json(
      { error: "unknown_action_class" },
      { status: 422 },
    );
  }
  const actionClass = message.action_class as ActionClass;

  // Re-check isGranted at click-time. Plan Phase 4.3 + TR8: revocation
  // race must fail-closed.
  const grant = await isGranted(supabase, user.id, actionClass);
  if (!grant) {
    return NextResponse.json(
      { error: "no_active_grant", action_class: actionClass },
      { status: 403 },
    );
  }

  // Reject autonomous tiers — Send is not the founder-initiated path for
  // these. (auto runs at producer-time; auto_with_digest runs at producer-
  // time and emerges in the daily digest UI — PR-I.)
  if (grant.tier === "auto" || grant.tier === "auto_with_digest") {
    return NextResponse.json(
      {
        error: "send_not_applicable_for_tier",
        tier: grant.tier,
        action_class: actionClass,
      },
      { status: 400 },
    );
  }

  const confirmedTyped = body.confirmed_typed === true;
  const typedValue =
    typeof body.typed_value === "string" ? body.typed_value : undefined;

  // approve_every_time gate. Server-side re-validation per TR6 (load-
  // bearing TOM). No .trim() / .normalize() per Kieran P2-7 — case-
  // sensitive exact match.
  if (grant.tier === "approve_every_time") {
    if (!confirmedTyped || typedValue !== "SEND") {
      // Look up grant_id for the founder/action_class so the route's
      // 409 payload doesn't have to roundtrip again. RLS owner-select
      // is the gate; no service-role.
      const { data: grantRow } = await supabase
        .from("scope_grants")
        .select("id")
        .eq("founder_id", user.id)
        .eq("action_class", actionClass)
        .is("revoked_at", null)
        .order("granted_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      return NextResponse.json(
        {
          error: "requires_confirmation",
          action_class: actionClass,
          tier: grant.tier,
          recipient_excerpt: (message.draft_preview ?? "").slice(0, 200),
          message_id: message.id,
          grant_id: grantRow?.id ?? null,
        },
        { status: 409 },
      );
    }
  }

  // grant_id lookup for write-action-send.
  const { data: grantRow, error: grantSelErr } = await supabase
    .from("scope_grants")
    .select("id")
    .eq("founder_id", user.id)
    .eq("action_class", actionClass)
    .is("revoked_at", null)
    .order("granted_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (grantSelErr || !grantRow) {
    reportSilentFallback(grantSelErr ?? new Error("grant_row_missing"), {
      feature: "dashboard-send",
      op: "grant-id-select",
      message: "Failed to resolve grant_id for action_sends row",
      extra: { userId: user.id, actionClass },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }

  // recipient + body content: PR-I producers will wire real outbound
  // adapters. PR-H accepts what the founder provides via the click body
  // (typed-confirm modal echoes the body content so the signature is
  // bound to exactly what they confirmed seeing). Fallbacks keep the
  // hash inputs deterministic in the no-body case.
  const recipientIdentifier =
    typeof body.recipient_identifier === "string"
      ? body.recipient_identifier
      : `__pending__:${message.id}`;
  const bodyContent =
    typeof body.body_content === "string"
      ? body.body_content
      : (message.draft_preview ?? "");

  try {
    const written = await writeActionSend({
      supabase,
      founderId: user.id,
      message: {
        id: message.id as string,
        action_class: actionClass,
        draft_preview: (message.draft_preview as string | null) ?? null,
      },
      grant: { id: grantRow.id as string, tier: grant.tier },
      tier: grant.tier,
      confirmedTyped,
      typedValue,
      recipientIdentifier,
      bodyContent,
      templateHash: templateHashFor(
        {
          action_class: actionClass,
          owning_domain: (message.owning_domain as string | null) ?? null,
        },
        grant.tier,
      ),
    });

    // Flip the draft to archived. RLS owner-update.
    const { error: archiveErr } = await supabase
      .from("messages")
      .update({ status: "archived" })
      .eq("id", message.id)
      .eq("user_id", user.id);
    if (archiveErr) {
      reportSilentFallback(archiveErr, {
        feature: "dashboard-send",
        op: "messages-archive",
        message:
          "action_sends row written but messages.status archive failed (orphan record)",
        extra: { userId: user.id, messageId, actionSendId: written.id },
      });
      // The action_sends row IS the load-bearing artefact; archive
      // failure is non-fatal at the route layer.
    }

    Sentry.addBreadcrumb({
      category: "dashboard-send",
      message: "send.completed",
      level: "info",
      data: { action_class: actionClass, tier: grant.tier },
    });

    return NextResponse.json({
      id: written.id,
      action_class: actionClass,
      tier: grant.tier,
    });
  } catch {
    // writeActionSend already mirrors via reportSilentFallback.
    return NextResponse.json({ error: "send_failed" }, { status: 500 });
  }
}
