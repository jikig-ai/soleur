import type { IncomingMessage, ServerResponse } from "http";
import * as Sentry from "@sentry/nextjs";
import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "@/server/observability";

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

  // Verify conversation ownership
  // Stage 4 review F3 (#2886): also fetch `workflow_ended_at` so the chat
  // surface can hydrate its `workflowEnded` flag on reload of an already-
  // ended conversation. Without this, the in-memory lifecycle slice
  // initializes to `idle` and the input renders enabled.
  const { data: conv, error: convErr } = await supabase
    .from("conversations")
    .select("id, total_cost_usd, input_tokens, output_tokens, workflow_ended_at")
    .eq("id", conversationId)
    .eq("user_id", user.id)
    .single();

  if (convErr || !conv) {
    reportSilentFallback(convErr ?? null, {
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
  const { data: messages, error: msgErr } = await supabase
    .from("messages")
    .select(
      "id, role, content, leader_id, created_at, message_attachments(id, storage_path, filename, content_type, size_bytes)",
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

  // Diagnostic breadcrumb gated on the pathological case only: a 200 with
  // zero messages for a row that ownership-checked successfully is the H1
  // signal (row mismatch or genuinely empty thread). Logging on every
  // success would burn the 100-entry breadcrumb buffer with noise that
  // displaces useful UI/navigation context when an unrelated error fires
  // later in the same request scope.
  // TODO(#3267): if Sentry shows this firing alongside client-side
  // `op: "history-fetch-no-session"` events for the same conversationId,
  // add an `X-Resumed-Count` response header so the WS-handler's
  // `messageCount` can be cross-checked against this empty-200 path
  // (H4 disambiguation). Level bumped from `info` to `warning` so the
  // breadcrumb survives Sentry's per-event downsampling and remains
  // visible in triage when a downstream UI exception captures.
  const messageCount = messages?.length ?? 0;
  if (messageCount === 0) {
    Sentry.addBreadcrumb({
      category: "kb-chat",
      message: "history-fetch-success-empty",
      level: "warning",
      data: { conversationId, count: 0 },
    });
  }

  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({
    messages: messages ?? [],
    totalCostUsd: Number(conv.total_cost_usd ?? 0),
    inputTokens: conv.input_tokens ?? 0,
    outputTokens: conv.output_tokens ?? 0,
    workflowEndedAt: conv.workflow_ended_at ?? null,
  }));
}
