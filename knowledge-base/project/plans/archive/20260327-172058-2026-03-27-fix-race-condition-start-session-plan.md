---
title: "fix: race condition on session.conversationId with concurrent start_session"
type: fix
date: 2026-03-27
deepened: 2026-03-27
---

# fix: race condition on session.conversationId with concurrent start_session

## Enhancement Summary

**Deepened on:** 2026-03-27
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Acceptance Criteria, Test Scenarios)

### Key Improvements

1. Discovered that `resume_session` has the same race condition -- overwrites `session.conversationId` without aborting the prior active session
2. Proposed extracting a shared `abortActiveSession()` helper to eliminate duplication across `start_session`, `resume_session`, and `close_conversation`
3. Identified a one-message-leak timing window in the `for await` loop after abort signal fires
4. Added error-resilience guidance: abort must fire synchronously before the async DB update to guarantee cleanup even if the update fails

### New Considerations Discovered

- `resume_session` handler (lines 146-171) is a second entry point for the same race condition
- Extracting a helper reduces three near-identical abort sequences to one, making future changes atomic
- The Supabase status update should use `.catch()` rather than blocking the new session creation on DB success

## Overview

When a user sends `start_session` twice in quick succession, the second call creates a new `conversationId` and overwrites `session.conversationId` before the first agent session finishes. Messages from the first session continue streaming to the client via `sendToClient(userId, ...)`, mixing conversations. The second `start_session` must abort the active agent session for the current `session.conversationId` before replacing it.

## Problem Statement

In `apps/web-platform/server/ws-handler.ts`, the `start_session` handler (lines 114-141):

1. Creates a new conversation via `createConversation()`
2. Overwrites `session.conversationId` with the new ID
3. Fires `startAgentSession()` (fire-and-forget with `.catch()`)
4. Sends `session_started` to the client

There is no check for an existing `session.conversationId` or active agent session. The `startAgentSession` function in `agent-runner.ts` does abort existing sessions -- but only for the *same* `userId:conversationId` key. A new `start_session` creates a *new* conversation ID, so the abort check in `startAgentSession` (line 247) never matches the old session.

**Result:** Two agent sessions run concurrently for the same user. Both call `sendToClient(userId, ...)`, so stream messages from conversation A interleave with messages from conversation B in the client UI.

**Discovered during:** Post-merge review of #1190 (multi-turn conversation continuity).

### Research Insights

**The same race exists in `resume_session`:** The `resume_session` handler (lines 146-171) sets `session.conversationId = msg.conversationId` without checking for or aborting a prior active session. If a user resumes a different conversation while one is still streaming, the same interleaving occurs. Both handlers need the abort guard.

**`sendToClient` routes by `userId`, not `conversationId`:** The `sendToClient` function (line 55-59) looks up the session by `userId` and sends on whatever WebSocket is registered. It has no concept of which conversation the message belongs to. This means any active `startAgentSession` call for the same user will deliver messages to the same socket, regardless of which conversation produced them.

**`activeSessions` in agent-runner uses `userId:conversationId` keys:** The Map in agent-runner.ts (line 54) is keyed by `userId:conversationId`. When `start_session` creates a new conversation, the old entry (`userId:oldConvId`) is never looked up or cleaned, so the old session continues running in memory until its `for await` loop completes or the AbortController fires.

**Node.js single-threaded guarantee helps:** WebSocket messages are processed sequentially by the Node.js event loop. Two rapid `start_session` messages cannot truly race in the parallel-execution sense -- the second waits for the first `handleMessage` call to reach an `await` point. This means the abort-then-replace guard does not need locking or atomic compare-and-swap. The guard just needs to run synchronously before the first `await` in the handler.

## Proposed Solution

Add an abort-then-replace guard at the top of both `start_session` and `resume_session` in `ws-handler.ts`. Extract a shared helper to eliminate duplication.

### Extract `abortActiveSession` helper in `ws-handler.ts`

Create a helper function that encapsulates the abort-cleanup pattern already used in `close_conversation`:

```typescript
/**
 * Abort the active agent session for this user, if any, and mark the
 * conversation as completed. Call synchronously before overwriting
 * session.conversationId with a new value.
 *
 * The abortSession() call is synchronous (fires AbortController.abort()),
 * guaranteeing the agent's for-await loop will break on the next iteration.
 * The DB status update is fire-and-forget -- if it fails, the conversation
 * is left in "active" status but the agent is already dead; the startup
 * orphan cleanup (cleanupOrphanedConversations) will catch it.
 */
function abortActiveSession(userId: string, session: ClientSession): void {
  if (!session.conversationId) return;

  const oldConvId = session.conversationId;
  console.log(`[ws] Aborting active session ${oldConvId} for user ${userId} (superseded)`);

  // 1. Abort the agent runner (synchronous -- fires AbortController.abort())
  abortSession(userId, oldConvId);

  // 2. Mark old conversation as completed (fire-and-forget)
  supabase
    .from("conversations")
    .update({ status: "completed", last_active: new Date().toISOString() })
    .eq("id", oldConvId)
    .then(({ error }) => {
      if (error) {
        console.error(`[ws] Failed to mark conversation ${oldConvId} as completed: ${error.message}`);
      }
    });

  // 3. Clear the conversation ID before caller sets the new one
  session.conversationId = undefined;
}
```

### Apply to `start_session` handler

```typescript
case "start_session": {
  try {
    abortActiveSession(userId, session);

    console.log(`[ws] start_session for user ${userId}, leader ${msg.leaderId}`);
    const conversationId = await createConversation(userId, msg.leaderId);
    session.conversationId = conversationId;
    // ... rest unchanged
```

### Apply to `resume_session` handler

```typescript
case "resume_session": {
  try {
    abortActiveSession(userId, session);

    // Verify conversation ownership
    const { data: conv, error: convErr } = await supabase
      // ... rest unchanged
```

### Refactor `close_conversation` to reuse

```typescript
case "close_conversation": {
  if (!session.conversationId) {
    sendToClient(userId, { type: "error", message: "No active session." });
    return;
  }

  try {
    abortActiveSession(userId, session);
    sendToClient(userId, { type: "session_ended", reason: "closed" });
  } catch (err) {
    // ...
  }
  break;
}
```

Note: `close_conversation` currently awaits the Supabase update before sending `session_ended`. Switching to fire-and-forget via the helper changes the ordering slightly -- `session_ended` may arrive before the DB update completes. This is acceptable because the client does not depend on DB status; it only needs the WebSocket confirmation. If strict ordering is preferred, `close_conversation` can keep its existing inline `await` pattern instead of using the helper.

### Why "completed" not "failed"

The old conversation was intentionally superseded by the user, not lost due to an error. Using `"completed"` keeps the conversation history accessible and avoids false alarms in monitoring. The `close_conversation` handler already uses `"completed"` for the same pattern (user-initiated close).

### Why fire-and-forget for the DB update

The `abortSession()` call is the critical operation -- it fires `AbortController.abort()` synchronously, which causes the agent's `for await` loop to break on the next iteration. The DB status update is a bookkeeping operation. Making it fire-and-forget means:

1. The new session starts immediately (no waiting for a DB round-trip that could be slow under load)
2. If the DB update fails, the `cleanupOrphanedConversations()` function (agent-runner.ts line 189) catches stale `"active"` conversations on server startup
3. Consistent with the pattern in the `close` event handler (ws-handler.ts line 441-447) which also does fire-and-forget abort with deferred cleanup

### No changes to `agent-runner.ts`

The `startAgentSession` function's existing abort logic (line 247: `const existing = activeSessions.get(key)`) is correct for its scope -- it prevents duplicate sessions for the same conversation. The race condition is in the *caller* (`ws-handler.ts`) which fails to clean up the *previous* conversation's session before creating a new one.

### No changes to client

The client (`ws-client.ts`) does not need changes. It receives `session_started` with the new `conversationId` and uses that for subsequent messages. The abort of the old session on the server side is invisible to the client -- stream messages from the old session will stop arriving because `abortSession` triggers `controller.signal.aborted` which breaks the `for await` loop in `startAgentSession`.

### Edge Cases

**One-message leak window:** After `abortSession()` fires, the old session's `for await` loop (agent-runner.ts line 448) may have already pulled one more message from the SDK iterator before checking `controller.signal.aborted` (line 449). At most one extra `stream` message could leak to the client. This is inherent to the cooperative-abort pattern and is not fixable without SDK-level cancellation support. The impact is negligible -- one partial text chunk from the old conversation.

**Supabase update failure:** If the fire-and-forget DB update fails, the conversation stays in `"active"` status. This is caught by `cleanupOrphanedConversations()` which runs on server startup and marks stale active conversations as `"failed"`.

**AbortController double-abort:** If `close_conversation` is sent after the session was already aborted by a `start_session`, `abortActiveSession` returns early because `session.conversationId` is already `undefined`. No double-abort occurs.

## Acceptance Criteria

- [x] When a user sends `start_session` while an agent session is already active, the previous session is aborted before the new one starts (`apps/web-platform/server/ws-handler.ts`)
- [x] When a user sends `resume_session` while an agent session is already active, the previous session is aborted before the new one is associated
- [x] The previous conversation's status is updated to `"completed"` (not `"failed"`) in the database
- [x] No stream messages from the old session are delivered to the client after the new session starts (except the one-message leak window inherent to cooperative abort)
- [x] The `session_started` response for the new session is sent after the abort completes
- [x] A `start_session` with no prior active session (first session, or after `close_conversation`) works unchanged
- [x] The `close_conversation` handler is not affected (already handles cleanup correctly, optionally refactored to use shared helper)
- [x] A shared `abortActiveSession()` helper eliminates duplication across the three handlers
- [x] Add unit tests for the concurrent `start_session` and `resume_session` race condition scenarios to `apps/web-platform/test/ws-abort.test.ts`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/bug-fix change in existing WebSocket handler.

## Test Scenarios

- Given a user with an active agent session (conversationId A), when the user sends `start_session` for a new domain leader, then `abortSession(userId, conversationIdA)` is called before `createConversation` and conversation A status becomes `"completed"`
- Given a user with an active agent session (conversationId A), when the user sends `resume_session` for conversationId B, then `abortSession(userId, conversationIdA)` is called before setting conversationId to B
- Given a user with an active agent session, when the user sends `start_session` and the abort + DB update complete, then `session_started` is sent with the new conversationId and the old session's `for await` loop breaks on `controller.signal.aborted`
- Given a user with no active session (first connection), when the user sends `start_session`, then behavior is identical to current -- no abort is attempted
- Given a user who already called `close_conversation` (conversationId is undefined), when the user sends `start_session`, then the guard is skipped (no abort needed)
- Given a user who sends `start_session` twice with minimal delay, when both messages are processed sequentially by the Node.js event loop, then the first starts normally and the second aborts the first before starting
- Given a user with an active session, when `abortActiveSession` is called and the Supabase update fails, then the agent is still aborted (sync abort fires first) and the stale conversation is caught by `cleanupOrphanedConversations` on next restart
- Given a user who sends `close_conversation` after `start_session` already aborted the previous session, then `abortActiveSession` returns early because `session.conversationId` is already undefined

## Context

**Key files:**

- `apps/web-platform/server/ws-handler.ts` -- WebSocket message router, `start_session` handler (lines 114-141), `resume_session` (lines 146-171), `close_conversation` (lines 176-198)
- `apps/web-platform/server/agent-runner.ts` -- `abortSession()` export (line 61), `startAgentSession()` (line 237), `activeSessions` Map (line 54)
- `apps/web-platform/server/review-gate.ts` -- `AgentSession` interface, abort-aware promise
- `apps/web-platform/test/ws-protocol.test.ts` -- existing protocol tests

**Relevant learnings:**

- `2026-03-20-review-gate-promise-leak-abort-timeout.md` -- established the `abortSession()` pattern and abort-aware cleanup; key insight: every long-lived promise needs a cancellation path
- `2026-03-20-fire-and-forget-promise-catch-handler.md` -- `.catch()` on fire-and-forget `startAgentSession` calls; key insight: internal try/catch does not make fire-and-forget safe
- `2026-03-20-websocket-first-message-auth-toctou-race.md` -- async-with-state-mutation race pattern in ws-handler; key insight: check socket state after every await before mutating shared state
- `2026-03-27-agent-sdk-session-resume-architecture.md` -- multi-turn session architecture with SDK resume + message replay fallback

## References

- Related issue: #1194
- Found during: post-merge review of #1190
- Pattern: `close_conversation` handler (ws-handler.ts:176-198) already does abort + status update + clear conversationId
