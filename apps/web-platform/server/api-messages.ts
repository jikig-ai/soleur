import type { IncomingMessage, ServerResponse } from "http";
import * as Sentry from "@sentry/nextjs";
import { createServiceClient } from "@/lib/supabase/service";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";

// PR-C §2.2 (#3244): module-level service-role client is PERMANENT —
// used only for `supabase.auth.getUser(token)` at the route entry point
// to validate the HTTP Bearer token BEFORE userId exists. The 2 tenant
// `.from("conversations")` and `.from("messages")` sites below migrate
// to `getFreshTenantClient(user.id)`. See `.service-role-allowlist`
// entry rationale (PERMANENT — HTTP auth.getUser bootstrap).
const supabase = createServiceClient();

/**
 * GET /api/conversations/:id/messages
 *
 * Returns message history for a conversation, authenticated via
 * Authorization: Bearer <supabase_access_token>.
 */
export async function handleConversationMessages(
  req: IncomingMessage,
  res: ServerResponse,
  conversationId: string,
): Promise<void> {
  // Extract bearer token
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    reportSilentFallback(null, {
      feature: "kb-chat",
      op: "history-fetch-401-missing-auth",
      extra: { conversationId },
    });
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Missing authorization token" }));
    return;
  }

  const token = authHeader.slice(7);
  const {
    data: { user },
    error: authErr,
  } = await supabase.auth.getUser(token);

  if (authErr || !user) {
    reportSilentFallback(authErr ?? null, {
      feature: "kb-chat",
      op: "history-fetch-401-invalid-token",
      extra: { conversationId },
    });
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Invalid token" }));
    return;
  }

  // PR-C §2.2 (#3244): tenant-scoped client for the remaining reads.
  // Per-handler RLS-baseline probe per plan §0.4: catches mid-session
  // jti revocation or RLS policy churn that a cached JWT inside the
  // TTL window would otherwise mask. On probe failure, surface 500
  // (auth-domain dependency failed); the caller retries.
  let tenant;
  try {
    tenant = await getFreshTenantClient(user.id);
    const { error: probeErr } = await tenant
      .from("users")
      .select("id")
      .eq("id", user.id)
      .maybeSingle();
    if (probeErr) {
      reportSilentFallback(probeErr, {
        feature: "kb-chat",
        op: "history-fetch-auth-probe",
        extra: { conversationId, userId: user.id },
      });
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Auth probe failed" }));
      return;
    }
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      reportSilentFallback(err, {
        feature: "kb-chat",
        op: "history-fetch-auth-probe",
        extra: { conversationId, userId: user.id },
      });
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Auth probe failed" }));
      return;
    }
    throw err;
  }

  // Verify conversation ownership
  // Stage 4 review F3 (#2886): also fetch `workflow_ended_at` so the chat
  // surface can hydrate its `workflowEnded` flag on reload of an already-
  // ended conversation. Without this, the in-memory lifecycle slice
  // initializes to `idle` and the input renders enabled.
  // visibility-sweep: RLS returns own + workspace-shared conversations.
  // Also fetch user_id to gate cost columns for non-owners below.
  const { data: conv, error: convErr } = await tenant
    .from("conversations")
    .select(
      "id, user_id, total_cost_usd, input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens, workflow_ended_at, created_at",
    )
    .eq("id", conversationId)
    .single();

  if (convErr || !conv) {
    // Defense-in-depth (FR3): a row-absent 404 is the expected deferred-
    // conversation noise class (a fresh KB-chat open whose row has not
    // materialized yet, a multi-tab race, or a stale deep-link). Mirror at
    // WARNING level — consistent with the sibling empty-200 breadcrumb below
    // ("baseline noise from fresh-but-not-yet-written conversations is
    // accepted"). Genuine 401 (invalid-token) and 500 (auth-probe / messages-
    // load) sites keep reportSilentFallback (error) and continue to page. The
    // HTTP 404 status and op string are unchanged so the existing alert rule
    // and the client's `!res.ok` branch keep working.
    warnSilentFallback(convErr ?? null, {
      feature: "kb-chat",
      op: "history-fetch-404-not-owned-or-missing",
      extra: { conversationId, userId: user.id },
    });
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Conversation not found" }));
    return;
  }

  // Load messages — joined with `message_attachments` so the chat surface
  // can rehydrate attachment chips on reload (#3254). The relation is
  // FK'd via `message_attachments.message_id`; an empty array is the
  // expected shape for messages without attachments.
  // PR-C §2.2 (#3244): tenant-scoped. RLS on `messages` FK-joins through
  // `conversations.user_id`; the ownership-checked `conv.id` above
  // already gates this read, so no explicit user filter needed here.
  const { data: messages, error: msgErr } = await tenant
    .from("messages")
    .select(
      // `status` and `usage` (added in migration 040) carry the
      // aborted-turn marker + token cost + completed-actions snapshot
      // so PR2's history reload can render the marker for partial
      // assistant text persisted on Stop or tab-close. Without these
      // here, the live WS-subscriber would see the marker once and a
      // page reload would silently drop it (G2 disclosure regression).
      // `message_kind` (migration 105) discriminates the durable per-turn
      // summary (`'turn_summary'`) from ordinary text (NULL). Without it here,
      // a reloaded summary row hydrates as a plain text bubble (silent render
      // regression — same class as the status/usage note above).
      "id, role, content, leader_id, created_at, status, usage, message_kind, message_attachments(id, storage_path, filename, content_type, size_bytes)",
    )
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true });

  if (msgErr) {
    reportSilentFallback(msgErr, {
      feature: "kb-chat",
      op: "history-fetch-500-messages-load",
      extra: { conversationId },
    });
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Failed to load messages" }));
    return;
  }

  // 200 with zero messages on an ownership-checked row — diagnostic for
  // the empty-banner class. `warning` (raised from `info` in #3267) so it
  // survives Sentry's per-event downsampling. Some baseline noise from
  // fresh-but-not-yet-written conversations is accepted.
  // TODO(#3267): if this co-fires with client `history-fetch-no-session`
  // for the same conversationId, add an `X-Resumed-Count` header so the
  // WS-handler's `messageCount` can be cross-checked (H4 disambiguation).
  const messageCount = messages?.length ?? 0;
  if (messageCount === 0) {
    Sentry.addBreadcrumb({
      category: "kb-chat",
      message: "history-fetch-success-empty",
      level: "warning",
      data: { conversationId, count: 0 },
    });
  }

  const isOwner = (conv as { user_id?: string }).user_id === user.id;

  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({
    messages: messages ?? [],
    totalCostUsd: isOwner ? Number(conv.total_cost_usd ?? 0) : 0,
    inputTokens: isOwner ? (conv.input_tokens ?? 0) : 0,
    outputTokens: isOwner ? (conv.output_tokens ?? 0) : 0,
    // Migration 041 — cache tokens persisted per-conversation. Surface
    // them in the resume response so the chat-surface cost badge can
    // render `(input + cache_read + cache_creation)` instead of
    // showing the uncached-input subset only (plan §Risks R8).
    cacheReadInputTokens: isOwner
      ? ((conv as { cache_read_input_tokens?: number | null })
          .cache_read_input_tokens ?? 0)
      : 0,
    cacheCreationInputTokens: isOwner
      ? ((conv as { cache_creation_input_tokens?: number | null })
          .cache_creation_input_tokens ?? 0)
      : 0,
    workflowEndedAt: conv.workflow_ended_at ?? null,
    // PR-B (#3603) — surface conversation start time so the chat surface can
    // gate the cohort-missing-reply marker on the row-absence cohort window.
    createdAt: conv.created_at ?? null,
  }));
}
