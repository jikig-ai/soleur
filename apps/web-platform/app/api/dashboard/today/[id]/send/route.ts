// PR-H (#4077) — POST /api/dashboard/today/[id]/send
//
// Founder-callable: completes a draft by re-checking the active scope_grant
// at click-time, writing the action_sends signature row, and flipping the
// message to archived. Branches on grant.tier:
//
//   - draft_one_click       → straight through; write action_sends + archive
//   - approve_every_time    → require confirmed_typed=true && typed_value="SEND"
//                              AND expected_draft_preview_hash echoing the
//                              hash returned in the prior 409; else
//                              409 requires_confirmation with a fresh hash
//   - auto / auto_with_digest → 400 (these are not founder-initiated paths)
//
// Trust model. The typed-confirm modal is the FIRST line of defense (UX
// TOM that gives the founder a beat-and-confirm moment). The SECOND line
// is server-side re-validation of (typed_value === "SEND" && hash echo).
// Both lines presume a non-compromised browser session — at the layer
// below, the supabase cookie + RLS owner-scope is the load-bearing tenant
// gate. An attacker holding the cookie can fully impersonate the founder
// regardless of UX gates; that broader concern is out-of-scope for the
// send endpoint and is mitigated at the session layer (httpOnly cookie,
// short-lived JWT, MFA on /login). PR-I will reconsider whether a server-
// issued single-use nonce should be added on top of the hash echo if the
// programmatic-agent attack surface becomes a first-class concern.
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
  // Hash of message.draft_preview at the time the server issued 409
  // requires_confirmation. The second POST MUST echo it; the server
  // re-reads draft_preview and recomputes the hash. Mismatch (e.g., a
  // concurrent Edit between the 409 and the confirm POST) returns 409
  // again with a fresh hash — closes the Send→Edit→Send race where the
  // founder confirms content A but a sibling tab edits to content B
  // before the second POST lands.
  expected_draft_preview_hash?: unknown;
}

function sha256Hex(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

function assertNeverTier(tier: never): never {
  // Compile-time exhaustiveness gate. Adding a 5th tier to
  // ActionClassTier without extending this switch trips tsc here
  // before reaching CI.
  throw new Error(`unhandled tier: ${String(tier)}`);
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

  // Exhaustive tier dispatch (assertNeverTier in default arm forces a
  // tsc error if a 5th ActionClassTier is added without updating this
  // switch). Reject autonomous tiers — Send is not the founder-
  // initiated path for these. (auto runs at producer-time;
  // auto_with_digest runs at producer-time and emerges in the daily
  // digest UI — PR-I.)
  switch (grant.tier) {
    case "auto":
    case "auto_with_digest":
      return NextResponse.json(
        {
          error: "send_not_applicable_for_tier",
          tier: grant.tier,
          action_class: actionClass,
        },
        { status: 400 },
      );
    case "draft_one_click":
    case "approve_every_time":
      break;
    default:
      assertNeverTier(grant.tier);
  }

  const confirmedTyped = body.confirmed_typed === true;
  const typedValue =
    typeof body.typed_value === "string" ? body.typed_value : undefined;
  const clientExpectedHash =
    typeof body.expected_draft_preview_hash === "string"
      ? body.expected_draft_preview_hash
      : undefined;

  // Server-derived send payload. PR-H stubs outbound: there is no
  // recipient column on messages yet (PR-I producers wire real adapters),
  // so recipientIdentifier is a stable per-message placeholder. The body
  // is the founder's current draft preview as the server sees it — NOT
  // a client-supplied field, which would let a malicious or compromised
  // client bind the approval signature to a body the founder never saw
  // (GDPR Art. 5(2) accountability — see DPD §2.3(q)).
  const draftPreview = (message.draft_preview as string | null) ?? "";
  const recipientIdentifier = `__pending__:${message.id}`;
  const bodyContent = draftPreview;
  const draftPreviewHash = sha256Hex(draftPreview);

  // approve_every_time gate. Server-side re-validation per TR6 (load-
  // bearing TOM). No .trim() / .normalize() per Kieran P2-7 — case-
  // sensitive exact match. Additionally binds the confirm payload to
  // the draft_preview hash returned in the prior 409 — a concurrent
  // Edit between the two POSTs trips this and forces re-confirmation
  // against the updated content.
  if (grant.tier === "approve_every_time") {
    const needsConfirmation =
      !confirmedTyped ||
      typedValue !== "SEND" ||
      clientExpectedHash !== draftPreviewHash;
    if (needsConfirmation) {
      return NextResponse.json(
        {
          error: "requires_confirmation",
          action_class: actionClass,
          tier: grant.tier,
          recipient_excerpt: recipientIdentifier,
          content_excerpt: draftPreview.slice(0, 2000),
          expected_draft_preview_hash: draftPreviewHash,
          message_id: message.id,
          grant_id: grant.id,
        },
        { status: 409 },
      );
    }
  }

  try {
    const written = await writeActionSend({
      supabase,
      founderId: user.id,
      message: {
        id: message.id as string,
        action_class: actionClass,
        draft_preview: draftPreview,
      },
      grant,
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
  } catch (err) {
    // 23505 unique_violation on action_sends(message_id) → another row
    // for this draft already exists (founder double-click, archive-
    // after-write split-brain producing a re-render of the card). The
    // immutable WORM table means we cannot rectify by overwrite — the
    // correct user-facing response is 409 "already_sent" so the UI can
    // refresh state instead of reporting a generic failure.
    const code =
      err && typeof err === "object" && "code" in err
        ? (err as { code?: unknown }).code
        : undefined;
    if (code === "23505") {
      return NextResponse.json(
        { error: "already_sent", message_id: messageId },
        { status: 409 },
      );
    }
    // writeActionSend already mirrors via reportSilentFallback.
    return NextResponse.json({ error: "send_failed" }, { status: 500 });
  }
}
