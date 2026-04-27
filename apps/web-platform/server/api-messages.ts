import type { IncomingMessage, ServerResponse } from "http";
import { createServiceClient } from "@/lib/supabase/service";

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
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Conversation not found" }));
    return;
  }

  // Load messages
  const { data: messages, error: msgErr } = await supabase
    .from("messages")
    .select("id, role, content, leader_id, created_at")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true });

  if (msgErr) {
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Failed to load messages" }));
    return;
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
