import { Server as HTTPServer } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { parse } from "url";
import { randomUUID } from "crypto";

import { KeyInvalidError, WS_CLOSE_CODES, type WSMessage, type Conversation } from "@/lib/types";
import type { ConversationContext } from "@/lib/types";
import { validateConversationContext } from "./context-validation";
import { createServiceClient } from "@/lib/supabase/service";
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
import * as Sentry from "@sentry/nextjs";
import { sanitizeErrorForClient } from "./error-sanitizer";
import { createChildLogger } from "./logger";
import {
  connectionThrottle,
  sessionThrottle,
  pendingConnections,
  extractClientIp,
  logRateLimitRejection,
} from "./rate-limiter";

const log = createChildLogger("ws");

// ---------------------------------------------------------------------------
// Supabase admin client (service role -- server-side only)
// ---------------------------------------------------------------------------
const supabase = createServiceClient();

// ---------------------------------------------------------------------------
// Session tracking
// ---------------------------------------------------------------------------
/** Grace period before aborting session on disconnect (allows reconnection). */
const DISCONNECT_GRACE_MS = 30_000;

/** Deferred conversation state — exists XOR conversationId exists. */
export interface PendingConversation {
  id: string;
  leaderId?: DomainLeaderId;
  context?: ConversationContext;
}

export interface ClientSession {
  ws: WebSocket;
  conversationId?: string;
  /** Deferred conversation (no DB row yet). Cleared when materialized or closed. */
  pending?: PendingConversation;
  /** Timer for deferred abort on disconnect — cleared if user reconnects. */
  disconnectTimer?: ReturnType<typeof setTimeout>;
  /** Timestamp of last user activity (auth or chat message). */
  lastActivity: number;
  /** Timer that closes the connection after WS_IDLE_TIMEOUT_MS of inactivity. */
  idleTimer?: ReturnType<typeof setTimeout>;
  /** Cached subscription status — set at auth, refreshed by billing check timer. */
  subscriptionStatus?: string;
}

/** Active connections keyed by Supabase user ID. */
export const sessions = new Map<string, ClientSession>();

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

  if (session.idleTimer) clearTimeout(session.idleTimer);
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
 * Returns true if the message was delivered via WebSocket, false if the
 * user has no active connection or the socket is not open.
 */
export function sendToClient(userId: string, message: WSMessage): boolean {
  const session = sessions.get(userId);
  if (!session || session.ws.readyState !== WebSocket.OPEN) return false;
  session.ws.send(JSON.stringify(message));
  return true;
}

/** Auth timeout: close unauthenticated connections after 5 seconds. */
const AUTH_TIMEOUT_MS = 5_000;

/** Idle timeout: close connections with no user activity (default 30 min). */
const WS_IDLE_TIMEOUT_MS = parseInt(process.env.WS_IDLE_TIMEOUT_MS ?? "1800000", 10);

/** Reset the idle timer for a session. Called after auth and on each chat message. */
function resetIdleTimer(userId: string, session: ClientSession): void {
  if (session.idleTimer) clearTimeout(session.idleTimer);
  session.lastActivity = Date.now();
  const timer = setTimeout(() => {
    log.info({ userId }, "Idle timeout — closing connection");
    session.ws.close(WS_CLOSE_CODES.IDLE_TIMEOUT, "Idle timeout");
  }, WS_IDLE_TIMEOUT_MS);
  timer.unref();
  session.idleTimer = timer;
}

/**
 * Check if user's subscription is suspended using cached session status.
 * Returns true if suspended (sends error and closes connection).
 */
function checkSubscriptionSuspended(userId: string, session: ClientSession): boolean {
  if (session.subscriptionStatus === "unpaid") {
    sendToClient(userId, {
      type: "error",
      message: "Your subscription is unpaid. Resolve payment to continue.",
    });
    session.ws.close(
      WS_CLOSE_CODES.SUBSCRIPTION_SUSPENDED,
      "Subscription suspended",
    );
    return true;
  }
  return false;
}

/**
 * Create a conversation row in the database and return its ID.
 */
async function createConversation(
  userId: string,
  leaderId?: DomainLeaderId,
  id?: string,
): Promise<string> {
  if (!id) id = randomUUID();

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

export async function handleMessage(userId: string, raw: string): Promise<void> {
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
      // Layer 3: Agent session creation rate limit (per-user, post-auth)
      if (!sessionThrottle.isAllowed(userId)) {
        logRateLimitRejection("session-limit", userId);
        sendToClient(userId, {
          type: "error",
          message: sanitizeErrorForClient(
            new Error("Rate limited: too many sessions"),
          ),
          errorCode: "rate_limited",
        });
        return;
      }

      try {
        // Validate context payload before any side effects
        let validatedContext: ConversationContext | undefined;
        try {
          validatedContext = validateConversationContext(msg.context);
        } catch (validationErr) {
          sendToClient(userId, {
            type: "error",
            message: (validationErr as Error).message,
          });
          return;
        }

        abortActiveSession(userId, session);

        // Defer conversation creation: generate UUID but don't insert into DB.
        // The row is created on the first real chat message.
        const pendingId = randomUUID();
        session.pending = { id: pendingId, leaderId: msg.leaderId, context: validatedContext };
        session.conversationId = undefined;

        log.info({ userId, leaderId: msg.leaderId ?? "auto-route", pendingId }, "start_session (deferred creation)");

        sendToClient(userId, { type: "session_started", conversationId: session.pending.id });
        resetIdleTimer(userId, session);
        log.debug("session_started sent to client");
      } catch (err) {
        Sentry.captureException(err);
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
        if (checkSubscriptionSuspended(userId, session)) return;

        abortActiveSession(userId, session);
        // Clear any pending deferred state — resuming an existing conversation
        session.pending = undefined;

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
        resetIdleTimer(userId, session);
        sendToClient(userId, {
          type: "session_started",
          conversationId: msg.conversationId,
        });
      } catch (err) {
        Sentry.captureException(err);
        log.error({ userId, err }, "resume_session error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // close_conversation: explicitly end the current conversation
    // ------------------------------------------------------------------
    case "close_conversation": {
      // Handle pending state (conversation never created in DB)
      if (!session.conversationId && session.pending) {
        session.pending = undefined;
        sendToClient(userId, { type: "session_ended", reason: "closed" });
        break;
      }

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
        Sentry.captureException(err);
        log.error({ userId, err }, "close_conversation error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // chat: forward user message into the running agent session
    // ------------------------------------------------------------------
    case "chat": {
      if (checkSubscriptionSuspended(userId, session)) return;

      if (!session.conversationId && !session.pending) {
        sendToClient(userId, {
          type: "error",
          message: "No active session. Send start_session first.",
        });
        return;
      }

      // Server-side attachment cap
      if (msg.attachments && msg.attachments.length > 5) {
        sendToClient(userId, {
          type: "error",
          message: "Too many files",
          errorCode: "too_many_files",
        });
        return;
      }

      // User activity resets idle timer
      resetIdleTimer(userId, session);

      // Materialize pending conversation on first real message
      if (!session.conversationId && session.pending) {
        const stripped = msg.content.replace(/@\w+\s*/g, "").trim();
        if (!stripped) {
          sendToClient(userId, {
            type: "error",
            message: "Please include a message along with the @-mention.",
          });
          return;
        }

        try {
          const { id: pendingId, leaderId: pendingLeader, context: pendingContext } = session.pending;
          await createConversation(userId, pendingLeader, pendingId);
          session.conversationId = pendingId;
          session.pending = undefined;

          log.info({ conversationId: session.conversationId, leaderId: pendingLeader ?? "auto-route" }, "Conversation materialized on first message");

          // Boot agent for directed sessions now that conversation exists
          if (pendingLeader) {
            startAgentSession(userId, session.conversationId, pendingLeader, undefined, undefined, pendingContext).catch(
              (err) => {
                Sentry.captureException(err);
                log.error({ userId, err }, "startAgentSession error");
                sendToClient(userId, {
                  type: "error",
                  message: sanitizeErrorForClient(err),
                  errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined,
                });
              },
            );
          }

          // sendUserMessage handles saveMessage internally — do not double-save
          await sendUserMessage(userId, session.conversationId, msg.content, pendingContext);
        } catch (err) {
          Sentry.captureException(err);
          log.error({ userId, err }, "chat error (deferred creation)");
          sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
        }
        break;
      }

      try {
        await sendUserMessage(
          userId,
          session.conversationId!,
          msg.content,
          undefined, // conversationContext
          msg.attachments,
        );
      } catch (err) {
        Sentry.captureException(err);
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
        Sentry.captureException(err);
        log.error({ userId, err }, "review_gate_response error");
        sendToClient(userId, {
          type: "error",
          message: sanitizeErrorForClient(err),
          gateId: msg.gateId,
        });
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
    case "tool_use":
    case "review_gate":
    case "session_started":
    case "session_ended":
    case "usage_update":
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

    // Layer 1: IP-based connection throttle (pre-auth)
    const clientIp = extractClientIp(req);
    if (!connectionThrottle.isAllowed(clientIp)) {
      logRateLimitRejection("connection-throttle", clientIp);
      // Fixed Retry-After to avoid leaking exact window config (CWE-209)
      socket.write(
        "HTTP/1.1 429 Too Many Requests\r\nRetry-After: 120\r\nConnection: close\r\n\r\n",
      );
      socket.destroy();
      return;
    }

    // Layer 2: Concurrent unauthenticated connection limit per IP
    if (!pendingConnections.add(clientIp)) {
      logRateLimitRejection("pending-limit", clientIp, {
        pending: pendingConnections.get(clientIp),
      });
      socket.write(
        "HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\n\r\n",
      );
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit("connection", ws, req, clientIp);
    });
  });

  // New connection — auth moves to first message
  wss.on("connection", (ws: WebSocket, _req: unknown, clientIp: string) => {
    let authenticated = false;
    let userId: string | null = null;

    // ---- Auth timeout: close if no auth message within 5 seconds ----
    const authTimer = setTimeout(() => {
      if (!authenticated) {
        ws.close(WS_CLOSE_CODES.AUTH_TIMEOUT, "Auth timeout");
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
          ws.close(WS_CLOSE_CODES.AUTH_REQUIRED, "Auth required");
          return;
        }

        if (msg.type !== "auth" || !msg.token) {
          clearTimeout(authTimer);
          ws.close(WS_CLOSE_CODES.AUTH_REQUIRED, "Auth required");
          return;
        }

        // Validate token via Supabase
        const {
          data: { user },
          error,
        } = await supabase.auth.getUser(msg.token);

        if (error || !user) {
          clearTimeout(authTimer);
          ws.close(WS_CLOSE_CODES.AUTH_TIMEOUT, "Unauthorized");
          return;
        }

        // Guard: if timeout fired during the await, socket is already closing
        if (ws.readyState !== WebSocket.OPEN) {
          clearTimeout(authTimer);
          return;
        }

        // Auth success — no longer pending
        clearTimeout(authTimer);
        authenticated = true;
        userId = user.id;
        pendingConnections.remove(clientIp);

        // Enforce T&C acceptance (version-aware) and cache subscription status
        const { data: userRow, error: tcError } = await supabase
          .from("users")
          .select("tc_accepted_version, subscription_status")
          .eq("id", user.id)
          .single();

        // Guard: socket may have closed during the await
        if (ws.readyState !== WebSocket.OPEN) {
          return;
        }

        if (tcError) {
          log.error({ userId: user.id, err: tcError.message }, "tc_accepted_version query failed");
          ws.close(WS_CLOSE_CODES.INTERNAL_ERROR, "Internal error");
          return;
        }

        if (userRow?.tc_accepted_version !== TC_VERSION) {
          ws.close(WS_CLOSE_CODES.TC_NOT_ACCEPTED, "T&C not accepted");
          return;
        }

        // If user already has an open socket, close the old one
        const existing = sessions.get(userId);
        if (existing && existing.ws.readyState === WebSocket.OPEN) {
          existing.ws.close(WS_CLOSE_CODES.SUPERSEDED, "Superseded by new connection");
        }

        // Register session — cancel any pending disconnect grace period
        const newSession: ClientSession = {
          ws,
          lastActivity: Date.now(),
          subscriptionStatus: userRow?.subscription_status ?? undefined,
        };
        sessions.set(userId, newSession);
        for (const [key, timer] of pendingDisconnects) {
          if (key.startsWith(`${userId}:`)) {
            clearTimeout(timer);
            pendingDisconnects.delete(key);
            log.info({ key }, "Cancelled pending disconnect (user reconnected)");
          }
        }
        log.info({ userId }, "User connected");

        // Start idle timer after auth
        resetIdleTimer(userId, newSession);

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
        Sentry.captureException(err);
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
      // If not yet authenticated, release the pending connection slot
      if (!authenticated) {
        pendingConnections.remove(clientIp);
      }
      if (userId) {
        const current = sessions.get(userId);
        if (current?.ws === ws) {
          if (current.idleTimer) clearTimeout(current.idleTimer);
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
      Sentry.captureException(err);
      log.error({ userId, err }, "Socket error");
    });
  });

  return wss;
}
