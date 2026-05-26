/**
 * Process-local registry of in-flight agent sessions.
 *
 * Extracted from `agent-runner.ts` for unit-testability of `abortSession`
 * (feat-abort-conversation-web PR1, plan §1.9). Lifting the Map +
 * abort helpers into a dependency-free module lets the abort tests
 * exercise broadcast/leader-keyed/cross-user/idempotency invariants
 * without spinning up the SDK + Supabase + observability surfaces that
 * `agent-runner.ts` pulls in at module-init time.
 *
 * Key shape:
 *   - `userId:conversationId` for single-leader (un-routed) sessions.
 *   - `userId:conversationId:leaderId` for multi-leader dispatch
 *     (`agent-runner.ts dispatchToLeaders`). Each leader runs its own
 *     `startAgentSession` closure and registers under its own key.
 *
 * Broadcast: an un-keyed `abortSession(userId, conversationId)` aborts
 * EVERY leader's session for the conversation by prefix-matching
 * `${userId}:${conversationId}` and `${userId}:${conversationId}:`.
 * This is load-bearing for the user-initiated Stop semantics — the
 * web-platform UX is "stop my conversation"; per-leader Stop is an
 * orchestration detail the user never sees (plan "Alternative Approaches
 * Considered"). Without broadcast, multi-leader turns could leave a
 * hidden leader session burning the user's BYOK key after Stop (G3).
 *
 * Process-local: see #2955 for the durable-state ADR; restart still
 * loses in-flight session bindings.
 */

import type { AgentSession } from "./review-gate";
import { SessionAbortError, type AbortKind } from "./abort-classifier";

const activeSessions = new Map<string, AgentSession>();

// Sidecar map for workspace association (feat-team-workspace-multi-user
// Phase 5.5 / Kieran C5). Keyed by userId (not sessionKey) because a single
// WS connection's current_organization_id is invariant for the connection
// lifetime — Phase 5.4's `supabase.auth.refreshSession()` on org-switch
// produces a fresh JWT which, in practice, drives a reconnect rather than
// repurposing the open socket. Multi-tab races covered by AC-FLOW3.
//
// abortAllWorkspaceMemberSessions matches `userId AND workspaceId` so that
// removing Harry from jikigai does NOT abort his sessions in his personal
// workspace (Kieran C5 correction).
const userWorkspaces = new Map<string, string>();

/** Compose the registry key for a session. Multi-leader dispatch uses
 *  the 3-segment form so per-leader cancellation is possible without
 *  killing sibling leaders. */
export function sessionKey(
  userId: string,
  conversationId: string,
  leaderId?: string,
): string {
  return leaderId
    ? `${userId}:${conversationId}:${leaderId}`
    : `${userId}:${conversationId}`;
}

/** Register a session in the process-local map. Overwrites any existing
 *  entry under the same key — the caller is expected to abort the
 *  prior session first (see `startAgentSession` in `agent-runner.ts`,
 *  which checks `activeSessions.get(key)` before set). */
export function registerSession(
  userId: string,
  conversationId: string,
  session: AgentSession,
  leaderId?: string,
): void {
  activeSessions.set(sessionKey(userId, conversationId, leaderId), session);
}

/** Remove a session from the registry. Called from the finally block of
 *  `startAgentSession` so a completed/errored/aborted turn doesn't leave
 *  a stale entry that blocks the next session start. */
export function unregisterSession(
  userId: string,
  conversationId: string,
  leaderId?: string,
): void {
  activeSessions.delete(sessionKey(userId, conversationId, leaderId));
}

/** Look up a single session by exact key. */
export function getSession(
  userId: string,
  conversationId: string,
  leaderId?: string,
): AgentSession | undefined {
  return activeSessions.get(sessionKey(userId, conversationId, leaderId));
}

/** Iterate every entry whose key matches the conversation prefix. Callers
 *  use this to find a review-gate resolver across leader keys. */
export function forEachSessionForConversation(
  userId: string,
  conversationId: string,
  fn: (key: string, session: AgentSession) => boolean | void,
): void {
  const prefix = `${userId}:${conversationId}`;
  for (const [key, session] of activeSessions) {
    if (key === prefix || key.startsWith(`${prefix}:`)) {
      const stop = fn(key, session);
      if (stop === true) return;
    }
  }
}

/**
 * Abort a running agent session.
 *
 * - When `leaderId` is provided, only that leader's session is aborted.
 * - When omitted, ALL sessions for `(userId, conversationId)` are aborted
 *   via prefix match — the load-bearing path for user-initiated Stop in
 *   multi-leader dispatch (plan §"Reconciliation" row 1).
 *
 * The Error message embeds `reason` so `agent-runner.ts`'s for-await
 * abort branch can read `controller.signal.reason` and route the
 * persistence + status-update logic via `classifyAbortReason` in
 * `abort-classifier.ts`.
 */
export function abortSession(
  userId: string,
  conversationId: string,
  reason?: AbortKind,
  leaderId?: string,
): void {
  const kind: AbortKind = reason ?? "disconnected";

  if (leaderId) {
    const session = activeSessions.get(sessionKey(userId, conversationId, leaderId));
    if (session) {
      session.abort.abort(new SessionAbortError(kind));
    }
    return;
  }

  // Broadcast: abort every session for this (userId, conversationId).
  const prefix = `${userId}:${conversationId}`;
  for (const [key, session] of activeSessions) {
    if (key === prefix || key.startsWith(`${prefix}:`)) {
      session.abort.abort(new SessionAbortError(kind));
    }
  }
}

/** Abort every session for a user. Called during account deletion. */
export function abortAllUserSessions(userId: string): void {
  const prefix = `${userId}:`;
  for (const [key, session] of activeSessions) {
    if (key.startsWith(prefix)) {
      session.abort.abort(new SessionAbortError("account_deleted"));
    }
  }
}

/**
 * Associate a userId with a current workspaceId (Phase 5.5 / Kieran C5).
 *
 * Called from ws-handler at session-open time (after the JWT current_organization_id
 * is resolved). The association is process-local and survives reconnects (the
 * sidecar map persists across socket close until explicitly cleared via
 * `clearUserWorkspace` on the FINAL disconnect path or until the entry is
 * overwritten by a fresh association on the next connection).
 *
 * Setting to undefined / empty is a no-op. Callers MUST resolve a real
 * workspaceId before invoking. Solo users carry workspaceId === userId per
 * the N2 invariant (migration 053 §1.1.7 backfill).
 */
export function setUserWorkspace(
  userId: string,
  workspaceId: string,
): void {
  if (!workspaceId) return;
  userWorkspaces.set(userId, workspaceId);
}

/** Remove a userId → workspaceId binding. Called on WS close. */
export function clearUserWorkspace(userId: string): void {
  userWorkspaces.delete(userId);
}

/** Inspect the current workspace binding for a user. Returns undefined when
 *  unbound (pre-Phase 5.5 sessions, or post-WS-close). */
export function getUserWorkspace(userId: string): string | undefined {
  return userWorkspaces.get(userId);
}

/**
 * Abort every session for a user whose current workspace binding equals
 * `workspaceId`. Called from `workspace-membership.ts:removeWorkspaceMember`
 * after the SQL RPC completes successfully (AC-FLOW2).
 *
 * Kieran C5: using `abortAllUserSessions(userId)` would over-kill — Harry
 * being removed from jikigai must NOT abort his sessions running against
 * his personal workspace. The membership check happens inside the SQL RPC
 * (atomic with the membership delete); this function fires only the
 * client-side SIGTERM equivalent. Sessions whose workspace binding does
 * not match the target workspaceId are left untouched.
 *
 * The cost-row for the partial run writes with `status='interrupted'` via
 * the for-await abort branch in `agent-runner.ts` reading the
 * `workspace_membership_revoked` `AbortKind` (see abort-classifier.ts).
 */
export function abortAllWorkspaceMemberSessions(
  workspaceId: string,
  userId: string,
): void {
  if (userWorkspaces.get(userId) !== workspaceId) return;
  const prefix = `${userId}:`;
  for (const [key, session] of activeSessions) {
    if (key.startsWith(prefix)) {
      session.abort.abort(new SessionAbortError("workspace_membership_revoked"));
    }
  }
}

/** Abort every session in the process. Called during server shutdown. */
export function abortAllSessions(): void {
  for (const [, session] of activeSessions) {
    session.abort.abort(new SessionAbortError("server_shutdown"));
  }
}

/**
 * Test-only helpers. The runtime never reads from `__test_only__`; tests
 * use `clear()` between cases to scrub the module-level Map. Exposing a
 * dedicated namespace beats exporting `activeSessions` directly because
 * it pins the surface area: any future test-helper additions land here
 * and stay grep-discoverable.
 */
export const __test_only__ = {
  clear: () => {
    activeSessions.clear();
    userWorkspaces.clear();
  },
  size: () => activeSessions.size,
  workspaceSize: () => userWorkspaces.size,
};
