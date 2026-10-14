import { WebSocket } from "ws";
import type { ClientSession } from "./ws-handler";

// Module-level Map so modules that need the count (/health, session-metrics)
// don't have to import the full ws-handler graph (Supabase client, Sentry,
// agent-runner) just to read `.size`. ws-handler re-exports this same Map.
//
// Holds the live WebSocket — host-local by definition (epic #5274). The
// disconnect-grace owning-host guard (ws-handler `runDisconnectGraceAbort`,
// ADR-068 §5) reads this to detect a same-host reconnect before aborting.
export const sessions = new Map<string, ClientSession>();

/**
 * feat-session-completion-inline — true when the user's live socket is bound
 * to `conversationId`, i.e. that conversation's chat surface is mounted (the
 * socket exists only while ChatSurface/useWebSocket is mounted — unmount
 * closes it). `notifyTaskCompleted` uses this to suppress the redundant
 * push/email nudge when the operator is watching the completion land inline.
 *
 * Signal provenance: `session.conversationId`'s single writer is the
 * ws-handler binding handshake (`start_session`/`resume_session`), cleared on
 * close/abort/supersede — the binding IS the session, so the signal cannot
 * outlive it. Residuals: a mounted-but-backgrounded tab still reads as
 * viewing (the card lands and is seen on return — acceptable for v1), and a
 * headless/external-agent socket bound to the same conversation reads as
 * viewing without a human present (worst case: no push, but the unread
 * inbox row + badge remain — the same accepted residual). If a clientKind
 * discriminator is ever added to ClientSession, this predicate is the
 * consumer.
 */
export function isConversationViewed(
  userId: string,
  conversationId: string,
): boolean {
  const session = sessions.get(userId);
  return (
    session !== undefined &&
    session.ws.readyState === WebSocket.OPEN &&
    session.conversationId === conversationId
  );
}
