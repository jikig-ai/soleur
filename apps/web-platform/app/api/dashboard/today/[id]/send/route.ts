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
import { hashUserId, reportSilentFallback } from "@/server/observability";
import {
  isTemplateAuthorized,
  PredicateException,
} from "@/server/templates/is-template-authorized";
import { getTemplateHash } from "@/server/templates/template-registry";
import logger from "@/server/logger";

// 5s ceiling on the template-authorization probe. Per plan §Phase 4 §4:
// exceeding this hard timeout fails-closed with 500 + Sentry capture
// (kind:template_predicate_timeout). The timeout is wrapped via
// Promise.race; the request is allowed to abandon the probe rather than
// block the founder's UI on a slow DB connection.
const PREDICATE_TIMEOUT_MS = 5_000;

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
    .select(
      "id, user_id, action_class, status, draft_preview, owning_domain, template_id",
    )
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

  // PR-I (#4078) — Template-authorization two-probe gate.
  // Fires AFTER isGranted and BEFORE the tier-specific confirm gate.
  // Only `draft_one_click` requires template authorization in v1; other
  // tiers (auto / auto_with_digest are rejected above; approve_every_time
  // gates on its own typed-confirm path). Plan §Phase 4 §4 + Sharp Edges.
  const founderIdHash = hashUserId(user.id);
  const templateHashForGate = getTemplateHash({
    template_id: (message.template_id as string | null) ?? "default_legacy",
  });
  if (grant.tier === "draft_one_click") {
    let predicateResult;
    try {
      // 5s race ceiling. On timeout the request fails 500 + Sentry tag.
      predicateResult = await Promise.race([
        isTemplateAuthorized(
          supabase,
          user.id,
          templateHashForGate,
          grant.id,
        ),
        new Promise<never>((_, reject) =>
          setTimeout(
            () => reject(new PredicateException("predicate timed out")),
            PREDICATE_TIMEOUT_MS,
          ),
        ),
      ]);
    } catch (err) {
      // Fail-closed: any predicate exception (DB error, timeout) is
      // 500 + Sentry capture. NEVER admitted as 'authorized'.
      reportSilentFallback(err, {
        feature: "dashboard-send",
        op: "template-authorize",
        message: "isTemplateAuthorized threw (fail-closed)",
        extra: {
          userId: user.id,
          messageId,
          actionClass,
          kind: "template_predicate_timeout",
        },
      });
      return NextResponse.json(
        { error: "internal_error", action_class: actionClass },
        { status: 500 },
      );
    }

    if (predicateResult.status === "denied") {
      // Per plan §Phase 4 §5: pino structured log on every denial. NO
      // Sentry mirror on routine denials (Art. 7(3) — denials are
      // expected behavior, not silent fallbacks). Sentry tags are
      // reserved for actual errors.
      logger.info(
        {
          feature: "template-authorizations",
          op: "denied",
          template_hash: templateHashForGate,
          action_class: actionClass,
          deny_reason: predicateResult.reason,
          founder_id_hash: founderIdHash,
        },
        "template-authorization denied",
      );
      return NextResponse.json(
        {
          error: "template_not_authorized",
          deny_reason: predicateResult.reason,
          action_class: actionClass,
        },
        { status: 403 },
      );
    }

    if (predicateResult.status === "first_send") {
      // First-send-IS-authorization (plan §Phase 4 §2 + §Sharp Edges).
      // The Send click on a labeled draft_one_click button IS the
      // Art. 7(3) "specific" + "informed" consent act. Write the
      // authorization row BEFORE proceeding to action_sends — if
      // writeActionSend fails downstream, the authorization row is
      // benign (next send sees it and branches as 'authorized').
      const { error: authErr } = await supabase.rpc("authorize_template", {
        p_template_hash: templateHashForGate,
        p_action_class: actionClass,
        p_grant_id: grant.id,
      });
      if (authErr) {
        reportSilentFallback(authErr, {
          feature: "dashboard-send",
          op: "authorize-template",
          message: "authorize_template RPC failed (first-send path)",
          extra: {
            userId: user.id,
            messageId,
            actionClass,
            kind: "template_authorization_race",
          },
        });
        return NextResponse.json(
          { error: "internal_error", action_class: actionClass },
          { status: 500 },
        );
      }
    }
    // status === 'authorized' → fall through unchanged.
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
        template_id: (message.template_id as string | null) ?? "default_legacy",
      },
      grant,
      tier: grant.tier,
      confirmedTyped,
      typedValue,
      recipientIdentifier,
      bodyContent,
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
