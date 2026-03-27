---
title: "fix: race condition on session.conversationId with concurrent start_session"
type: fix
date: 2026-03-27
---

# fix: race condition on session.conversationId with concurrent start_session

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

## Proposed Solution

Add an abort-then-replace guard at the top of the `start_session` case in `ws-handler.ts`. Before creating a new conversation, check if `session.conversationId` is set and, if so, abort the existing agent session and mark the old conversation as completed.

### Changes to `apps/web-platform/server/ws-handler.ts`

In the `start_session` case block, before `createConversation`:

1. Check if `session.conversationId` is already set (an active session exists)
2. If yes, call `abortSession(userId, session.conversationId)` to abort the running agent
3. Update the old conversation status to `"completed"` in Supabase (not `"failed"` -- the user intentionally switched, this is not an error)
4. Clear `session.conversationId` before proceeding with the new session setup

**Pseudocode:**

```typescript
// ws-handler.ts, start_session case, before createConversation()
case "start_session": {
  try {
    // Abort any active session before starting a new one
    if (session.conversationId) {
      abortSession(userId, session.conversationId);
      await supabase
        .from("conversations")
        .update({ status: "completed", last_active: new Date().toISOString() })
        .eq("id", session.conversationId);
      session.conversationId = undefined;
    }

    const conversationId = await createConversation(userId, msg.leaderId);
    session.conversationId = conversationId;
    // ... rest unchanged
```

### Why "completed" not "failed"

The old conversation was intentionally superseded by the user, not lost due to an error. Using `"completed"` keeps the conversation history accessible and avoids false alarms in monitoring. The `close_conversation` handler already uses `"completed"` for the same pattern (user-initiated close).

### No changes to `agent-runner.ts`

The `startAgentSession` function's existing abort logic (line 247: `const existing = activeSessions.get(key)`) is correct for its scope -- it prevents duplicate sessions for the same conversation. The race condition is in the *caller* (`ws-handler.ts`) which fails to clean up the *previous* conversation's session before creating a new one.

### No changes to client

The client (`ws-client.ts`) does not need changes. It receives `session_started` with the new `conversationId` and uses that for subsequent messages. The abort of the old session on the server side is invisible to the client -- stream messages from the old session will stop arriving because `abortSession` triggers `controller.signal.aborted` which breaks the `for await` loop in `startAgentSession`.

## Acceptance Criteria

- [ ] When a user sends `start_session` while an agent session is already active, the previous session is aborted before the new one starts (`apps/web-platform/server/ws-handler.ts`)
- [ ] The previous conversation's status is updated to `"completed"` (not `"failed"`) in the database
- [ ] No stream messages from the old session are delivered to the client after the new session starts
- [ ] The `session_started` response for the new session is sent after the abort completes
- [ ] A `start_session` with no prior active session (first session, or after `close_conversation`) works unchanged
- [ ] The `close_conversation` handler is not affected (already handles cleanup correctly)
- [ ] Add a unit test for the concurrent `start_session` race condition scenario to `apps/web-platform/test/ws-protocol.test.ts`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/bug-fix change in existing WebSocket handler.

## Test Scenarios

- Given a user with an active agent session (conversationId A), when the user sends `start_session` for a new domain leader, then `abortSession(userId, conversationIdA)` is called before `createConversation` and conversation A status becomes `"completed"`
- Given a user with an active agent session, when the user sends `start_session` and the abort + DB update complete, then `session_started` is sent with the new conversationId and the old session's `for await` loop breaks on `controller.signal.aborted`
- Given a user with no active session (first connection), when the user sends `start_session`, then behavior is identical to current -- no abort is attempted
- Given a user who already called `close_conversation` (conversationId is undefined), when the user sends `start_session`, then the guard is skipped (no abort needed)
- Given a user who sends `start_session` twice with minimal delay, when both messages are processed sequentially by the Node.js event loop, then the first starts normally and the second aborts the first before starting

## Context

**Key files:**

- `apps/web-platform/server/ws-handler.ts` -- WebSocket message router, `start_session` handler (lines 114-141)
- `apps/web-platform/server/agent-runner.ts` -- `abortSession()` export (line 61), `startAgentSession()` (line 237)
- `apps/web-platform/server/review-gate.ts` -- `AgentSession` interface, abort-aware promise
- `apps/web-platform/test/ws-protocol.test.ts` -- existing protocol tests

**Relevant learnings:**

- `2026-03-20-review-gate-promise-leak-abort-timeout.md` -- established the `abortSession()` pattern and abort-aware cleanup
- `2026-03-20-fire-and-forget-promise-catch-handler.md` -- `.catch()` on fire-and-forget `startAgentSession` calls
- `2026-03-20-websocket-first-message-auth-toctou-race.md` -- async-with-state-mutation race pattern in ws-handler
- `2026-03-27-agent-sdk-session-resume-architecture.md` -- multi-turn session architecture

## References

- Related issue: #1194
- Found during: post-merge review of #1190
- Pattern: `close_conversation` handler (ws-handler.ts:176-198) already does abort + status update + clear conversationId
