import { Server as HTTPServer } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { parse } from "url";
import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "crypto";

import { KeyInvalidError, type WSMessage, type Conversation } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { MAX_SELECTION_LENGTH } from "./review-gate";

// Agent runner stubs -- will be implemented in server/agent-runner.ts
import {
  startAgentSession,
  sendUserMessage,
  resolveReviewGate,
  abortSession,
} from "./agent-runner";
import { sanitizeErrorForClient } from "./error-sanitizer";
import { createChildLogger } from "./logger";

const log = createChildLogger("ws");

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
/** Grace period before aborting session on disconnect (allows reconnection). */
const DISCONNECT_GRACE_MS = 30_000;

export interface ClientSession {
  ws: WebSocket;
  conversationId?: string;
  /** Timer for deferred abort on disconnect — cleared if user reconnects. */
  disconnectTimer?: ReturnType<typeof setTimeout>;
}

/** Active connections keyed by Supabase user ID. */
const sessions = new Map<string, ClientSession>();

/** Deferred abort timers for disconnected sessions (keyed by userId:conversationId). */
const pendingDisconnects = new Map<string, ReturnType<typeof setTimeout>>();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Abort the active agent session for this user (if any), mark the conversation
 *  completed (fire-and-forget), and clear session.conversationId. No-ops if no
 *  conversation is active. */
export function abortActiveSession(userId: string, session: ClientSession): void {
  if (!session.conversationId) return;

  const oldConvId = session.conversationId;
  log.info({ userId, conversationId: oldConvId }, "Aborting active session (superseded)");

  abortSession(userId, oldConvId, "superseded");

  // Fire-and-forget — orphan cleanup catches failures on restart.
  // Supabase query builders return PromiseLike (not Promise), so use
  // .then(onFulfilled, onRejected) instead of .then().catch().
  supabase
    .from("conversations")
    .update({ status: "completed", last_active: new Date().toISOString() })
    .eq("id", oldConvId)
    .then(
      ({ error }) => {
        if (error) {
          log.error({ conversationId: oldConvId, err: error.message }, "Failed to mark conversation as completed");
        }
      },
      (err) => {
        log.error({ conversationId: oldConvId, err }, "Failed to update conversation");
      },
    );

  session.conversationId = undefined;
}

/**
 * Serialize and send a WSMessage to the client identified by `userId`.
 * No-ops silently if the user has no active connection or the socket is not open.
 */
export function sendToClient(userId: string, message: WSMessage): void {
  const session = sessions.get(userId);
  if (!session || session.ws.readyState !== WebSocket.OPEN) return;
  session.ws.send(JSON.stringify(message));
}

/** Auth timeout: close unauthenticated connections after 5 seconds. */
const AUTH_TIMEOUT_MS = 5_000;

/**
 * Create a conversation row in the database and return its ID.
 */
async function createConversation(
  userId: string,
  leaderId?: DomainLeaderId,
): Promise<string> {
  const id = randomUUID();

  const { error } = await supabase.from("conversations").insert({
    id,
    user_id: userId,
    domain_leader: leaderId ?? null,
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
  if (!session) {
    log.warn({ userId }, "No session found — message dropped");
    return;
  }

  log.debug({ userId, msgType: msg.type }, "Message received");

  switch (msg.type) {
    // ------------------------------------------------------------------
    // start_session: create conversation, boot agent, reply with ID
    // ------------------------------------------------------------------
    case "start_session": {
      try {
        abortActiveSession(userId, session);

        log.info({ userId, leaderId: msg.leaderId ?? "auto-route" }, "start_session");
        const conversationId = await createConversation(userId, msg.leaderId);
        session.conversationId = conversationId;
        log.info({ conversationId }, "Conversation created, booting agent");

        // Boot the agent runner (async -- streams will flow via sendToClient)
        startAgentSession(userId, conversationId, msg.leaderId, undefined, undefined, msg.context).catch(
          (err) => {
            log.error({ userId, err }, "startAgentSession error");
            sendToClient(userId, {
              type: "error",
              message: sanitizeErrorForClient(err),
              errorCode:
                err instanceof KeyInvalidError ? "key_invalid" : undefined,
            });
          },
        );

        sendToClient(userId, { type: "session_started", conversationId });
        log.debug("session_started sent to client");
      } catch (err) {
        log.error({ userId, err }, "start_session error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // resume_session: reconnect to an existing conversation
    // ------------------------------------------------------------------
    case "resume_session": {
      try {
        abortActiveSession(userId, session);

        // Verify conversation ownership
        const { data: conv, error: convErr } = await supabase
          .from("conversations")
          .select("id, status")
          .eq("id", msg.conversationId)
          .eq("user_id", userId)
          .single();

        if (convErr || !conv) {
          sendToClient(userId, { type: "error", message: "Conversation not found" });
          return;
        }

        session.conversationId = msg.conversationId;
        sendToClient(userId, {
          type: "session_started",
          conversationId: msg.conversationId,
        });
      } catch (err) {
        log.error({ userId, err }, "resume_session error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // close_conversation: explicitly end the current conversation
    // ------------------------------------------------------------------
    case "close_conversation": {
      if (!session.conversationId) {
        sendToClient(userId, {
          type: "error",
          message: "No active session.",
        });
        return;
      }

      try {
        const convId = session.conversationId;
        abortSession(userId, convId, "superseded");
        await supabase
          .from("conversations")
          .update({ status: "completed", last_active: new Date().toISOString() })
          .eq("id", convId);
        session.conversationId = undefined;
        sendToClient(userId, { type: "session_ended", reason: "closed" });
      } catch (err) {
        log.error({ userId, err }, "close_conversation error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
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
        log.error({ userId, err }, "chat error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
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
        // Layer 1: transport-level length guard (defense-in-depth)
        if (typeof msg.selection !== "string" || msg.selection.length > MAX_SELECTION_LENGTH) {
          throw new Error("Invalid review gate selection");
        }

        await resolveReviewGate(
          userId,
          session.conversationId,
          msg.gateId,
          msg.selection,
        );
      } catch (err) {
        log.error({ userId, err }, "review_gate_response error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // auth is handled at connection level, not here
    // ------------------------------------------------------------------
    case "auth": {
      sendToClient(userId, {
        type: "error",
        message: "Already authenticated.",
      });
      break;
    }

    // ------------------------------------------------------------------
    // Server -> client only types are ignored if received from client
    // ------------------------------------------------------------------
    case "auth_ok":
    case "stream":
    case "stream_start":
    case "stream_end":
    case "review_gate":
    case "session_started":
    case "session_ended":
    case "error": {
      sendToClient(userId, {
        type: "error",
        message: "This message type is server-to-client only.",
      });
      break;
    }

    default: {
      const _exhaustive: never = msg;
      sendToClient(userId, {
        type: "error",
        message: "Unknown message type.",
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

  // New connection — auth moves to first message
  wss.on("connection", (ws: WebSocket) => {
    let authenticated = false;
    let userId: string | null = null;

    // ---- Auth timeout: close if no auth message within 5 seconds ----
    const authTimer = setTimeout(() => {
      if (!authenticated) {
        ws.close(4001, "Auth timeout");
      }
    }, AUTH_TIMEOUT_MS);

    // ---- Heartbeat (Cloudflare terminates idle WS after 100s) ----
    let pingInterval: ReturnType<typeof setInterval> | undefined;

    // ---- Message handling ----
    ws.on("message", async (data) => {
      if (!authenticated) {
        // First message MUST be { type: "auth", token: "..." }
        let msg: { type: string; token?: string };
        try {
          msg = JSON.parse(data.toString());
        } catch {
          clearTimeout(authTimer);
          ws.close(4003, "Auth required");
          return;
        }

        if (msg.type !== "auth" || !msg.token) {
          clearTimeout(authTimer);
          ws.close(4003, "Auth required");
          return;
        }

        // Validate token via Supabase
        const {
          data: { user },
          error,
        } = await supabase.auth.getUser(msg.token);

        if (error || !user) {
          clearTimeout(authTimer);
          ws.close(4001, "Unauthorized");
          return;
        }

        // Guard: if timeout fired during the await, socket is already closing
        if (ws.readyState !== WebSocket.OPEN) {
          clearTimeout(authTimer);
          return;
        }

        // Auth success
        clearTimeout(authTimer);
        authenticated = true;
        userId = user.id;

        // Enforce T&C acceptance (version-aware)
        const { data: userRow, error: tcError } = await supabase
          .from("users")
          .select("tc_accepted_version")
          .eq("id", user.id)
          .single();

        // Guard: socket may have closed during the await
        if (ws.readyState !== WebSocket.OPEN) {
          return;
        }

        if (tcError) {
          log.error({ userId: user.id, err: tcError.message }, "tc_accepted_version query failed");
          ws.close(4005, "Internal error");
          return;
        }

        if (userRow?.tc_accepted_version !== TC_VERSION) {
          ws.close(4004, "T&C not accepted");
          return;
        }

        // If user already has an open socket, close the old one
        const existing = sessions.get(userId);
        if (existing && existing.ws.readyState === WebSocket.OPEN) {
          existing.ws.close(4002, "Superseded by new connection");
        }

        // Register session — cancel any pending disconnect grace period
        sessions.set(userId, { ws });
        for (const [key, timer] of pendingDisconnects) {
          if (key.startsWith(`${userId}:`)) {
            clearTimeout(timer);
            pendingDisconnects.delete(key);
            log.info({ key }, "Cancelled pending disconnect (user reconnected)");
          }
        }
        log.info({ userId }, "User connected");

        // Start heartbeat after auth
        pingInterval = setInterval(() => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.ping();
          }
        }, 30_000);

        ws.send(JSON.stringify({ type: "auth_ok" }));
        return;
      }

      // Authenticated — route to handleMessage
      handleMessage(userId!, data.toString()).catch((err) => {
        log.error({ userId, err }, "Unhandled message error");
        sendToClient(userId!, {
          type: "error",
          message: "Internal server error",
        });
      });
    });

    // ---- Cleanup on disconnect ----
    ws.on("close", () => {
      clearTimeout(authTimer);
      if (pingInterval) clearInterval(pingInterval);
      if (userId) {
        const current = sessions.get(userId);
        if (current?.ws === ws) {
          sessions.delete(userId);
          // Grace period: defer abort to allow reconnection
          if (current.conversationId) {
            const convId = current.conversationId;
            const uid = userId;
            const timer = setTimeout(() => {
              log.info({ userId: uid, conversationId: convId }, "Grace period expired, aborting session");
              abortSession(uid, convId);
            }, DISCONNECT_GRACE_MS);
            timer.unref();
            // Store timer so reconnecting user can cancel it
            pendingDisconnects.set(`${uid}:${convId}`, timer);
          }
        }
        log.info({ userId, gracePeriodSec: DISCONNECT_GRACE_MS / 1000 }, "User disconnected");
      }
    });

    ws.on("error", (err) => {
      log.error({ userId, err }, "Socket error");
    });
  });

  return wss;
}
