import { Server as HTTPServer, IncomingMessage } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { parse } from "url";
import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "crypto";

import type { WSMessage, Conversation } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";

// Agent runner stubs -- will be implemented in server/agent-runner.ts
import {
  startAgentSession,
  sendUserMessage,
  resolveReviewGate,
} from "./agent-runner";

// ---------------------------------------------------------------------------
// Supabase admin client (service role -- server-side only)
// ---------------------------------------------------------------------------
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

// ---------------------------------------------------------------------------
// Session tracking
// ---------------------------------------------------------------------------
interface ClientSession {
  ws: WebSocket;
  conversationId?: string;
}

/** Active connections keyed by Supabase user ID. */
const sessions = new Map<string, ClientSession>();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Serialize and send a WSMessage to the client identified by `userId`.
 * No-ops silently if the user has no active connection or the socket is not open.
 */
export function sendToClient(userId: string, message: WSMessage): void {
  const session = sessions.get(userId);
  if (!session || session.ws.readyState !== WebSocket.OPEN) return;
  session.ws.send(JSON.stringify(message));
}

/**
 * Authenticate an incoming WebSocket upgrade request.
 * Expects `?token=<supabase_access_token>` on the connection URL.
 * Returns the authenticated user ID or null.
 */
async function authenticateConnection(
  req: IncomingMessage,
): Promise<string | null> {
  const { query } = parse(req.url || "", true);
  const token = query.token as string | undefined;

  if (!token) return null;

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(token);

  if (error || !user) return null;
  return user.id;
}

/**
 * Create a conversation row in the database and return its ID.
 */
async function createConversation(
  userId: string,
  leaderId: DomainLeaderId,
): Promise<string> {
  const id = randomUUID();

  const { error } = await supabase.from("conversations").insert({
    id,
    user_id: userId,
    domain_leader: leaderId,
    status: "active" as Conversation["status"],
    last_active: new Date().toISOString(),
  });

  if (error) {
    throw new Error(`Failed to create conversation: ${error.message}`);
  }

  return id;
}

// ---------------------------------------------------------------------------
// Message router
// ---------------------------------------------------------------------------

async function handleMessage(userId: string, raw: string): Promise<void> {
  let msg: WSMessage;

  try {
    msg = JSON.parse(raw) as WSMessage;
  } catch {
    sendToClient(userId, { type: "error", message: "Invalid JSON" });
    return;
  }

  const session = sessions.get(userId);
  if (!session) return; // should never happen inside a message handler

  switch (msg.type) {
    // ------------------------------------------------------------------
    // start_session: create conversation, boot agent, reply with ID
    // ------------------------------------------------------------------
    case "start_session": {
      try {
        const conversationId = await createConversation(userId, msg.leaderId);
        session.conversationId = conversationId;

        // Boot the agent runner (async -- streams will flow via sendToClient)
        startAgentSession(userId, conversationId, msg.leaderId);

        sendToClient(userId, { type: "session_started", conversationId });
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Failed to start session";
        sendToClient(userId, { type: "error", message });
      }
      break;
    }

    // ------------------------------------------------------------------
    // chat: forward user message into the running agent session
    // ------------------------------------------------------------------
    case "chat": {
      if (!session.conversationId) {
        sendToClient(userId, {
          type: "error",
          message: "No active session. Send start_session first.",
        });
        return;
      }

      try {
        await sendUserMessage(
          userId,
          session.conversationId,
          msg.content,
        );
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Failed to send message";
        sendToClient(userId, { type: "error", message });
      }
      break;
    }

    // ------------------------------------------------------------------
    // review_gate_response: resolve a pending review gate in the agent
    // ------------------------------------------------------------------
    case "review_gate_response": {
      if (!session.conversationId) {
        sendToClient(userId, {
          type: "error",
          message: "No active session.",
        });
        return;
      }

      try {
        await resolveReviewGate(
          userId,
          session.conversationId,
          msg.gateId,
          msg.selection,
        );
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Failed to resolve review gate";
        sendToClient(userId, { type: "error", message });
      }
      break;
    }

    // ------------------------------------------------------------------
    // Server -> client only types are ignored if received from client
    // ------------------------------------------------------------------
    case "stream":
    case "review_gate":
    case "session_started":
    case "session_ended":
    case "error": {
      sendToClient(userId, {
        type: "error",
        message: `Message type "${msg.type}" is server-to-client only.`,
      });
      break;
    }

    default: {
      const _exhaustive: never = msg;
      sendToClient(userId, {
        type: "error",
        message: `Unknown message type: ${(msg as { type: string }).type}`,
      });
      // Prevent unused-variable lint error
      void _exhaustive;
    }
  }
}

// ---------------------------------------------------------------------------
// Public entry point — called from server/index.ts
// ---------------------------------------------------------------------------

export function setupWebSocket(server: HTTPServer) {
  const wss = new WebSocketServer({ noServer: true });

  // Handle HTTP -> WebSocket upgrade on /ws path
  server.on("upgrade", (req, socket, head) => {
    const { pathname } = parse(req.url || "", true);

    if (pathname !== "/ws") {
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit("connection", ws, req);
    });
  });

  // New connection
  wss.on("connection", async (ws: WebSocket, req: IncomingMessage) => {
    // ---- Auth gate ----
    const userId = await authenticateConnection(req);

    if (!userId) {
      ws.close(4001, "Unauthorized");
      return;
    }

    // If user already has an open socket, close the old one
    const existing = sessions.get(userId);
    if (existing && existing.ws.readyState === WebSocket.OPEN) {
      existing.ws.close(4002, "Superseded by new connection");
    }

    // Register session
    sessions.set(userId, { ws });
    console.log(`[ws] User ${userId} connected`);

    // ---- Heartbeat (Cloudflare terminates idle WS after 100s) ----
    const pingInterval = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }
    }, 30_000);

    // ---- Message handling ----
    ws.on("message", (data) => {
      handleMessage(userId, data.toString()).catch((err) => {
        console.error(`[ws] Unhandled error for user ${userId}:`, err);
        sendToClient(userId, {
          type: "error",
          message: "Internal server error",
        });
      });
    });

    // ---- Cleanup on disconnect ----
    ws.on("close", () => {
      clearInterval(pingInterval);
      // Only delete if the session still points to THIS socket
      // (guards against race where a new connection already replaced it)
      const current = sessions.get(userId);
      if (current?.ws === ws) {
        sessions.delete(userId);
      }
      console.log(`[ws] User ${userId} disconnected`);
    });

    ws.on("error", (err) => {
      console.error(`[ws] Socket error for user ${userId}:`, err);
    });
  });

  return wss;
}
