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
// Ordering contract (#10543): durable approval row (action_sends, WORM) →
// ACCEPTED enqueue → archive. An enqueue that is not accepted leaves the draft
// visible and the row replayable: the founder's re-click re-dispatches the SAME
// event id (agent-spawn-<actionSendId>) from the existing row, never a second
// row. A replay is bound to the whole approval (draft hash, action class,
// tier) and capped at 23h so Inngest's ~24h event dedup is never straddled.
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
import {
  hashUserId,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { tierRequiresTemplateAuth } from "@/server/templates/is-template-authorized";
import { getTemplateHash } from "@/server/templates/template-registry";
import { runTemplateGate } from "@/server/templates/run-template-gate";
import { enqueueAgentSpawn } from "@/server/action-sends/enqueue-agent-spawn";
import { isTransientFetchError } from "@/server/inngest/send-with-retry";
import { parseSourceRef } from "@/server/inngest/agent-acknowledgment-templates";
import { verifiedUserId } from "@/server/request-auth";

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

// A replay older than this is refused: Inngest dedups an event id for ~24h and the consumer can leave
// acknowledged_at/failure_reason NULL on a run that executed, so an older replay could post a second
// artifact. 23h leaves a 1h margin (plan-level choice, not verified against the DB clock; CTO R1).
const REPLAY_MAX_AGE_MS = 23 * 60 * 60 * 1000;

interface ActionSendLookupRow {
  id: string;
  per_send_body_sha256: string | null;
  action_class: string;
  tier_at_send: string;
  clicked_at: string | null;
  acknowledged_at: string | null;
  failure_reason: string | null;
  undone_at: string | null;
  cancellation_requested_at: string | null;
}

// Read-only, cookie-scoped (owner RLS) lookup of an existing approval row for this draft.
async function lookupActionSend(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string,
  messageId: string,
): Promise<{ row: ActionSendLookupRow | null; error: unknown }> {
  const { data, error } = await supabase
    .from("action_sends")
    .select(
      "id, per_send_body_sha256, action_class, tier_at_send, clicked_at, acknowledged_at, failure_reason, undone_at, cancellation_requested_at",
    )
    .eq("message_id", messageId)
    .eq("user_id", userId)
    .maybeSingle();
  return { row: (data as ActionSendLookupRow | null) ?? null, error };
}

// Flip the draft to archived. RLS owner-update; filtered on status = 'draft' so a concurrent
// state change is never overwritten. Failure is non-fatal at the route layer: the action_sends
// row IS the load-bearing artefact, and a re-click finds it again.
async function archiveDraft(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string,
  messageId: string,
  actionSendId: string,
): Promise<void> {
  const { error: archiveErr } = await supabase
    .from("messages")
    .update({ status: "archived" })
    .eq("id", messageId)
    .eq("user_id", userId)
    .eq("status", "draft");
  if (archiveErr) {
    reportSilentFallback(archiveErr, {
      feature: "dashboard-send",
      op: "messages-archive",
      message:
        "action_sends row written but messages.status archive failed (orphan record)",
      extra: { userId, messageId, actionSendId },
    });
  }
}

export async function POST(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/today/[id]/send", origin);

  const supabase = await createClient();
  const userId = await verifiedUserId(req);
  if (!userId) {
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
      "id, user_id, action_class, status, draft_preview, owning_domain, template_id, source_ref",
    )
    .eq("id", messageId)
    .eq("user_id", userId) // belt-and-suspenders alongside RLS
    .maybeSingle();

  if (msgErr) {
    reportSilentFallback(msgErr, {
      feature: "dashboard-send",
      op: "messages-select",
      message: "Failed to load message for send",
      extra: { userId, messageId },
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

  // `messageIdStr` hoist keeps the action-class typed-literal lint (PR-H
  // ADR-034 §1) from flagging the implicit Supabase `any` widen at the send.
  const messageIdStr: string = String(message.id);
  const sourceRef: string =
    typeof message.source_ref === "string" ? message.source_ref : "";
  // Pure and local, so it is hoisted ahead of the lookup: whether anything
  // would be dispatched decides which replay arm a pending row takes.
  let parsed: ReturnType<typeof parseSourceRef> | null = null;
  if (sourceRef) {
    try {
      parsed = parseSourceRef(sourceRef);
    } catch {
      parsed = null;
    }
  }

  // #10543 — look up an existing approval row BEFORE the gates. Only the arms
  // that dispatch nothing are ungated here (a terminal row, a row with no
  // dispatchable source_ref, an expired approval): gating them would only
  // produce a spurious 403/409 on a draft that needs archiving. Every arm
  // that DOES dispatch (the replay) still passes every gate below.
  const { row: existing, error: lookupErr } = await lookupActionSend(
    supabase,
    userId,
    messageIdStr,
  );
  if (lookupErr) {
    reportSilentFallback(lookupErr, {
      feature: "dashboard-send",
      op: "action-sends-lookup",
      message: "Failed to look up an existing approval row for send",
      extra: { userId, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }

  let replay = false;
  if (existing) {
    const terminal =
      existing.acknowledged_at !== null ||
      existing.failure_reason !== null ||
      existing.undone_at !== null ||
      existing.cancellation_requested_at !== null;
    if (terminal) {
      // The run already settled (or was cancelled/undone). The mounted
      // LeaderLoopStatus is driven by the real row state, so the client
      // treats already_sent as a soft success.
      await archiveDraft(supabase, userId, messageIdStr, existing.id);
      return NextResponse.json(
        { error: "already_sent", message_id: messageId },
        { status: 409 },
      );
    }
    if (!parsed) {
      // Nothing would be dispatched for this source_ref shape: finish the
      // archive that a previous click could not.
      await archiveDraft(supabase, userId, messageIdStr, existing.id);
      return NextResponse.json({
        id: existing.id,
        action_class: actionClass,
        tier: existing.tier_at_send,
        action_send_id: existing.id,
        artifact_view_url: "",
        ...(sourceRef ? { degraded: "no_artifact_in_pr_a" as const } : {}),
      });
    }
    // `age >= 0` and isFinite make an unparseable, null or future clicked_at
    // fail closed to expiry rather than replaying.
    const age = Date.now() - Date.parse(existing.clicked_at ?? "");
    if (!(Number.isFinite(age) && age >= 0 && age <= REPLAY_MAX_AGE_MS)) {
      await archiveDraft(supabase, userId, messageIdStr, existing.id);
      warnSilentFallback(null, {
        feature: "spawn-agent",
        op: "inngest-replay-stale",
        message:
          "approval replay refused: action_sends row older than the replay window",
        extra: {
          userId,
          messageId,
          actionSendId: existing.id,
          replay: true,
        },
      });
      return NextResponse.json(
        { error: "approval_expired", message_id: messageId },
        { status: 409 },
      );
    }
    // The approval is bound to the body the founder saw: a NULL or different
    // stored hash means the draft changed since. Runs BEFORE isGranted so a
    // refused replay never reaches the template gate (whose first-send
    // authorization has a side effect). The draft is kept: recoverable.
    if (existing.per_send_body_sha256 !== draftPreviewHash) {
      reportSilentFallback(null, {
        feature: "spawn-agent",
        op: "replay-draft-changed",
        message:
          "approval replay refused: draft changed since the approval row was written",
        extra: {
          userId,
          messageId,
          actionSendId: existing.id,
          replay: true,
        },
      });
      return NextResponse.json(
        { error: "draft_changed_since_approval", message_id: messageId },
        { status: 409 },
      );
    }
    replay = true;
  }

  // Re-check isGranted at click-time. Plan Phase 4.3 + TR8: revocation
  // race must fail-closed.
  const grant = await isGranted(supabase, userId, actionClass);
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

  // A replay re-dispatches an approval written under a specific class and
  // tier; if either changed since, the approval no longer matches what the
  // founder is now allowed to do. Before the template gate so a refused
  // replay has no side effect.
  if (
    replay &&
    existing &&
    (existing.action_class !== actionClass ||
      existing.tier_at_send !== grant.tier)
  ) {
    reportSilentFallback(null, {
      feature: "spawn-agent",
      op: "replay-draft-changed",
      message:
        "approval replay refused: action class or tier changed since the approval row was written",
      extra: { userId, messageId, actionSendId: existing.id, replay: true },
    });
    return NextResponse.json(
      { error: "draft_changed_since_approval", message_id: messageId },
      { status: 409 },
    );
  }

  // PR-I (#4078) — Template-authorization two-probe gate.
  // Fires AFTER isGranted and BEFORE the tier-specific confirm gate.
  // Only `draft_one_click` requires template authorization in v1; the
  // `tierRequiresTemplateAuth` helper carries an exhaustive switch
  // over ActionClassTier so a future 5th tier fails tsc until it
  // declares its stance. Orchestration (5s timeout, fail-closed,
  // first-send-IS-authorization RPC dispatch, pino denial log) is
  // extracted to `runTemplateGate` per multi-agent review
  // (code-quality F3). Plan §Phase 4 §4 + Sharp Edges + ADR-035.
  if (tierRequiresTemplateAuth(grant.tier)) {
    const templateHashForGate = getTemplateHash({
      template_id: (message.template_id as string | null) ?? "default_legacy",
    });
    const gate = await runTemplateGate({
      supabase,
      founderId: userId,
      founderIdHash: hashUserId(userId),
      templateHash: templateHashForGate,
      grantId: grant.id,
      actionClass,
      messageId,
    });
    switch (gate.kind) {
      case "predicate_error":
      case "authorize_error":
        return NextResponse.json(
          { error: "internal_error", action_class: actionClass },
          { status: 500 },
        );
      case "deny":
        return NextResponse.json(
          {
            error: "template_not_authorized",
            deny_reason: gate.denyReason,
            action_class: actionClass,
          },
          { status: 403 },
        );
      case "allow":
        // Fall through to the tier-specific gate (approve_every_time
        // typed-confirm) + writeActionSend.
        break;
      default: {
        const _exhaustive: never = gate;
        void _exhaustive;
      }
    }
  }

  const confirmedTyped = body.confirmed_typed === true;
  const typedValue =
    typeof body.typed_value === "string" ? body.typed_value : undefined;
  const clientExpectedHash =
    typeof body.expected_draft_preview_hash === "string"
      ? body.expected_draft_preview_hash
      : undefined;

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

  // The approval row: reuse the existing one on a replay (never a second
  // row), otherwise write it. The try wraps ONLY the write, so a failure
  // later (enqueue, archive) can never be mistaken for an insert failure.
  let actionSendId: string;
  if (replay && existing) {
    actionSendId = existing.id;
  } else {
    try {
      const written = await writeActionSend({
        supabase,
        founderId: userId,
        message: {
          id: message.id as string,
          action_class: actionClass,
          draft_preview: draftPreview,
          template_id:
            (message.template_id as string | null) ?? "default_legacy",
        },
        grant,
        tier: grant.tier,
        confirmedTyped,
        typedValue,
        recipientIdentifier,
        bodyContent,
      });
      actionSendId = written.id;
    } catch (err) {
      // 23505 unique_violation on action_sends(message_id): a concurrent
      // click won the insert race (the lookup above found no row). The
      // immutable WORM table cannot be rectified by overwrite, and this
      // loser must neither dispatch nor archive: the next click finds the
      // winner's pending row and replays it.
      const code =
        err && typeof err === "object" && "code" in err
          ? (err as { code?: unknown }).code
          : undefined;
      if (code === "23505") {
        return NextResponse.json(
          { error: "send_in_progress", message_id: messageId },
          { status: 409 },
        );
      }
      // writeActionSend already mirrors via reportSilentFallback.
      return NextResponse.json({ error: "send_failed" }, { status: 500 });
    }
  }

  // PR-A scope: the deterministic stub only emits artifacts for source-ref
  // shapes that carry (owner, repo, number): `pr-*`, `issue-*`,
  // `secret-scan-*` (per github-on-event.ts:deriveSourceRef). Other shapes —
  // `ci-<run_id>`, `cve-GHSA-...`, `link-<hash>`, `anchor-<hash>` — have no
  // per-class GitHub target in PR-A (per-class resolution lands in PR-B,
  // #4360), so no Inngest event is enqueued (it would deadletter as
  // malformed_source_ref and spam Sentry) and the response carries
  // `degraded: "no_artifact_in_pr_a"` so the card renders an honest pill.
  //
  // installationId is OMITTED from the event payload by design — the
  // Inngest function server-resolves it from users.github_installation_id
  // keyed by founderId per AC2 (see enqueue-agent-spawn.ts).
  let degraded: "no_artifact_in_pr_a" | undefined;
  let artifactViewUrl = "";

  if (parsed) {
    artifactViewUrl = parsed.isPr
      ? `https://github.com/${parsed.owner}/${parsed.repo}/pull/${parsed.number}`
      : `https://github.com/${parsed.owner}/${parsed.repo}/issues/${parsed.number}`;
    try {
      await enqueueAgentSpawn({
        founderId: userId,
        messageId: messageIdStr,
        actionClass,
        sourceRef,
        actionSendId,
      });
    } catch (sendErr) {
      // Not accepted: keep the draft visible and the approval row replayable.
      // null first argument keeps the feature/op tags on the pino mirror
      // (#10542 ruling); extra carries identifiers only.
      reportSilentFallback(null, {
        feature: "spawn-agent",
        op: "inngest-enqueue",
        message:
          "inngest.send failed after retries; approval row stays committed and replayable, draft not archived",
        extra: {
          userId,
          messageId,
          actionSendId,
          errorName: sendErr instanceof Error ? sendErr.name : "unknown",
          replay,
          transient: isTransientFetchError(sendErr),
        },
      });
      return NextResponse.json(
        {
          error: "enqueue_unavailable",
          action_send_id: actionSendId,
          retryable: true,
        },
        { status: 503, headers: { "Retry-After": "5" } },
      );
    }
    if (replay) {
      warnSilentFallback(null, {
        feature: "spawn-agent",
        op: "inngest-enqueue-replay",
        message: "approval replay dispatched after a prior enqueue failure",
        extra: { userId, messageId, actionSendId, replay: true },
      });
    }
  } else if (sourceRef) {
    degraded = "no_artifact_in_pr_a";
  }

  // Ordering contract: approval row → ACCEPTED enqueue → archive.
  await archiveDraft(supabase, userId, messageIdStr, actionSendId);

  Sentry.addBreadcrumb({
    category: "dashboard-send",
    message: "send.completed",
    level: "info",
    data: { action_class: actionClass, tier: grant.tier },
  });

  return NextResponse.json({
    id: actionSendId,
    action_class: actionClass,
    tier: grant.tier,
    action_send_id: actionSendId,
    artifact_view_url: artifactViewUrl,
    ...(degraded ? { degraded } : {}),
  });
}
