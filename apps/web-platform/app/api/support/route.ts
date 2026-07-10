// POST /api/support — the in-app support chat's streaming transport
// (feat-wire-concierge-support-chat, ADR-109 / CTO Option D).
//
// This route is DELIBERATELY decoupled from the Command Center WebSocket
// (server/ws-handler.ts): the WS is single-per-user (supersedeExistingUserSocket)
// and support is a concurrent conversation, so support streams over its OWN HTTP
// Server-Sent-Events response instead of the shared WS. It reuses the finished
// support execution verbatim: `dispatchSoleurGo` takes `sendToClient` as an
// injected sink, so we hand it an SSE-writing adapter and pass `persona:"support"`.
//
// It imports NEITHER ws-handler's `sendToClient` NOR the `sessions` map — that
// isolation is what mechanically guarantees a support turn cannot disturb a
// Command Center session (asserted by test/support-route-isolation.test.ts).

import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { dispatchSoleurGo } from "@/server/cc-dispatcher";
import { resolveOrCreateSupportConversation } from "@/server/support-conversation";
import { formatSupportSseFrame } from "@/lib/support-sse";
import { sanitizeErrorForClient } from "@/server/error-sanitizer";
import { reportSilentFallback } from "@/server/observability";
import type { WSMessage } from "@/lib/types";

export async function POST(request: Request): Promise<Response> {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/support", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  const userId = user.id;

  const body = (await request.json().catch(() => null)) as { message?: unknown } | null;
  const message = typeof body?.message === "string" ? body.message.trim() : "";
  if (message.length === 0) {
    return new Response(JSON.stringify({ error: "Missing message" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Resolve-or-create the repo-less kind='support' conversation BEFORE opening the
  // stream so a failure returns a clean 500 (the client then shows its canned
  // fallback) rather than a half-open stream. dispatchSoleurGo requires a
  // persisted row (ownership probe / workspace_id / messages FK).
  let conversationId: string;
  try {
    conversationId = await resolveOrCreateSupportConversation(userId);
  } catch (err) {
    reportSilentFallback(err, { feature: "support", op: "support-route.resolveConversation", extra: { userId } });
    return new Response(JSON.stringify({ error: "Support is unavailable right now." }), {
      status: 503,
      headers: { "Content-Type": "application/json" },
    });
  }

  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let closed = false;
      const enqueue = (msg: WSMessage): boolean => {
        if (closed) return false;
        try {
          controller.enqueue(encoder.encode(formatSupportSseFrame(msg)));
          return true;
        } catch {
          return false;
        }
      };

      try {
        // The injected SSE sink — this is the whole coupling to the Concierge:
        // dispatchSoleurGo streams its frames here instead of the WS.
        await dispatchSoleurGo({
          userId,
          conversationId,
          userMessage: message,
          currentRouting: { kind: "soleur_go_pending" },
          sendToClient: (_uid: string, msg: WSMessage) => enqueue(msg),
          // Support has no sticky workflow (persona short-circuits routing).
          persistActiveWorkflow: async () => {},
          persona: "support",
        });
      } catch (err) {
        reportSilentFallback(err, { feature: "support", op: "support-route.dispatch", extra: { userId, conversationId } });
        // Surface an honest error frame the client renders as a support bubble.
        enqueue({ type: "error", message: sanitizeErrorForClient(err) } as WSMessage);
      } finally {
        closed = true;
        try {
          controller.close();
        } catch {
          // already closed
        }
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
