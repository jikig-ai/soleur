import type { DomainLeaderId } from "./domain-leaders";
import { sendToClient } from "./ws-handler";

// Agent sessions keyed by `${userId}:${conversationId}`
const activeSessions = new Map<string, AbortController>();

/**
 * Start a new agent session for a user + conversation.
 * Streams output to the client via WebSocket.
 */
export async function startAgentSession(
  userId: string,
  conversationId: string,
  leaderId: DomainLeaderId,
): Promise<void> {
  const key = `${userId}:${conversationId}`;

  // Abort any existing session for this user
  const existing = activeSessions.get(key);
  if (existing) existing.abort();

  const controller = new AbortController();
  activeSessions.set(key, controller);

  try {
    // TODO: Import and call Agent SDK query() here
    // For now, send a placeholder response
    sendToClient(userId, {
      type: "stream",
      content: `[Agent SDK placeholder] Session started with ${leaderId} leader. Agent SDK integration pending.`,
      partial: false,
    });

    sendToClient(userId, {
      type: "session_ended",
      reason: "Agent SDK not yet integrated",
    });
  } catch (err) {
    if (!controller.signal.aborted) {
      const message =
        err instanceof Error ? err.message : "Agent session failed";
      sendToClient(userId, { type: "error", message });
    }
  } finally {
    activeSessions.delete(key);
  }
}

/**
 * Send a user message into a running agent session.
 */
export async function sendUserMessage(
  _userId: string,
  _conversationId: string,
  _content: string,
): Promise<void> {
  // TODO: Feed message into Agent SDK streaming input
  throw new Error("Agent SDK multi-turn not yet implemented");
}

/**
 * Resolve a pending review gate in the agent session.
 */
export async function resolveReviewGate(
  _userId: string,
  _conversationId: string,
  _gateId: string,
  _selection: string,
): Promise<void> {
  // TODO: Resolve canUseTool callback promise
  throw new Error("Review gates not yet implemented");
}
