---
title: "fix: send resume_session when opening existing conversations"
type: fix
date: 2026-04-12
---

# fix: send resume\_session when opening existing conversations

## Enhancement Summary

**Deepened on:** 2026-04-12
**Sections enhanced:** 4 (Proposed Solution, Reconnection, Test Scenarios, Edge Cases)
**Research sources:** 6 institutional learnings, server-side code analysis

### Key Improvements

1. Added race condition analysis for reconnect state reset (from TOCTOU learning)
2. Added edge case for disconnect grace period interaction with resume\_session
3. Strengthened reconnection handling with defensive state clear pattern (from 2026-04-02 learning)
4. Added server-side validation detail showing fresh session is always blank after auth

### New Considerations Discovered

- Server creates a blank `ClientSession` on every new auth (line 603 of ws-handler.ts) -- confirms client MUST send session init after every `auth_ok`
- Disconnect grace period (30s) cancels pending abort timers on reconnect (line 605-611) -- `resume_session` on reconnect correctly resets the server-side conversation binding
- The `abortActiveSession` pattern (from ws-session-race learning) already runs in `resume_session` handler -- no additional abort logic needed on the client

## Overview

When a user navigates to an existing conversation page (URL contains a real
conversation UUID), the WebSocket client authenticates but never sends a
`resume_session` message to the server. The server-side session therefore has
neither `conversationId` nor `pending` set. When the user sends a chat message
(with or without attachments), the server rejects it with:

> Error: No active session. Send start\_session first.

The bug is not specific to attachments -- it affects **all messages** sent on a
returning conversation. The attachment scenario just happens to be the first time
the user noticed because the conversation was previously working (CTO had
responded) and the user returned to follow up.

## Root Cause

`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
lines 89-93:

```typescript
useEffect(() => {
  if (status === "connected" && conversationId === "new" && !sessionStarted && !contextLoading) {
    startSession(leaderId ?? undefined, kbContext);
    setSessionStarted(true);
  }
}, [status, conversationId, leaderId, sessionStarted, startSession, contextLoading, kbContext]);
```

The session initialization only fires when `conversationId === "new"`. For
existing conversations (UUID in URL), **no** `start_session` or `resume_session`
is ever sent. The server-side `resume_session` handler exists
(`ws-handler.ts:238-268`) and the protocol type is defined
(`lib/types.ts:56`), but the client never invokes it.

### Why it worked before

Prior to the deferred creation refactor (#1971), the session flow may have been
different. The `resume_session` protocol was added in #1190 for multi-turn
continuity but was never wired into the client-side page component. Conversations
that started as "new" and were used within the same WebSocket connection worked
because `session.conversationId` was set during the initial `start_session`
flow. The bug manifests specifically when:

1. User starts a conversation (gets `session_started` + `conversationId`)
2. User navigates away or refreshes the page
3. User returns to the conversation page (URL has the real UUID)
4. New WebSocket connection opens, authenticates, but **no** session
   initialization message is sent
5. User sends a message and gets "No active session"

## Proposed Solution

Add a `resume_session` call on the client side for existing conversations. Two
changes are needed:

### Change 1: Expose `resumeSession` from `ws-client.ts`

Add a `resumeSession` function to the `useWebSocket` hook that sends a
`resume_session` message to the server.

**File:** `apps/web-platform/lib/ws-client.ts`

Add alongside the existing `startSession` callback:

```typescript
const resumeSession = useCallback(
  (targetConversationId: string) => {
    setSessionConfirmed(false);
    send({ type: "resume_session", conversationId: targetConversationId });
  },
  [send],
);
```

Return `resumeSession` from the hook.

#### Research Insights (Change 1)

**Server-side contract:** The `resume_session` handler (`ws-handler.ts:238-268`)
does three things: (1) calls `abortActiveSession` to clean up any prior session
(including pending deferred state -- per learning 2026-04-11), (2) verifies
conversation ownership via Supabase query, (3) sets `session.conversationId`
and sends `session_started`. No agent session is started -- the agent boots
lazily when the first `chat` message arrives via `sendUserMessage`, which checks
for an in-memory session or falls back to history replay.

**Why `resume_session` and not `start_session`:** Using `start_session` for
existing conversations would generate a new UUID and create a deferred pending
state, orphaning the existing conversation. `resume_session` explicitly binds
to an existing conversation ID and verifies ownership.

### Change 2: Call `resumeSession` for existing conversations on the chat page

**File:**
`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

Modify the session initialization `useEffect` (lines 89-93) to handle both
new and existing conversations:

```typescript
useEffect(() => {
  if (status !== "connected" || sessionStarted) return;

  if (conversationId === "new") {
    if (!contextLoading) {
      startSession(leaderId ?? undefined, kbContext);
      setSessionStarted(true);
    }
  } else {
    // Existing conversation -- resume the server-side session
    resumeSession(conversationId);
    setSessionStarted(true);
  }
}, [status, conversationId, leaderId, sessionStarted, startSession, resumeSession, contextLoading, kbContext]);
```

### Change 3: Handle reconnection

When the WebSocket reconnects (transient failure), the `connect()` function
resets `sessionConfirmed` to false. However, `sessionStarted` is component
state that persists across reconnections. The `useEffect` above won't re-fire
because `sessionStarted` is already true.

Two options:

**Option A (preferred):** Reset `sessionStarted` when connection status
transitions to `"reconnecting"`. Add a new `useEffect`:

```typescript
useEffect(() => {
  if (status === "reconnecting") {
    setSessionStarted(false);
  }
}, [status]);
```

This allows the session initialization `useEffect` to re-fire after
reconnection. For existing conversations, it re-sends `resume_session`. For
new conversations, it re-sends `start_session`.

**Option B:** Move session initialization into the `auth_ok` handler inside
`ws-client.ts`. This would centralize the logic but would require passing
`conversationId` deeper into the hook and mixing concerns.

**Decision:** Option A is simpler and maintains the current separation of
concerns.

#### Research Insights (Change 3)

**Defensive state clear pattern (learning 2026-04-02):** The `useEffect` that
calls `connect()` already clears `lastError`, `disconnectReason`, and
`sessionConfirmed` at setup time. The `sessionStarted` reset should follow
the same pattern -- clear stale state before starting new state. The
`reconnect()` callback already resets `lastError` and `disconnectReason`;
`sessionStarted` is the missing piece.

**Server creates blank sessions on every auth (ws-handler.ts:603):** On each
new WebSocket connection, after auth succeeds, the server runs:

```typescript
const newSession: ClientSession = { ws, lastActivity: Date.now() };
sessions.set(userId, newSession);
```

This means after any reconnection, the server has no knowledge of which
conversation the client was viewing. The client MUST re-send `resume_session`
(or `start_session`) after every `auth_ok` -- there is no server-side state
that survives a WebSocket reconnection.

**Disconnect grace period interaction:** The server's 30-second grace period
(`DISCONNECT_GRACE_MS`) defers agent session abort on disconnect. When the
client reconnects, the server cancels pending disconnect timers (line 605-611).
However, the disconnect timer only preserves the **agent** session -- it does
NOT preserve the `ClientSession.conversationId` binding (the session is deleted
from the map at line 649 on disconnect). This confirms `resume_session` must be
re-sent even within the grace window.

**TOCTOU consideration:** The reconnect `useEffect` reset is safe because React
state updates (`setSessionStarted(false)`) are batched and processed
synchronously within a render cycle. The subsequent `useEffect` that sends
`resume_session` runs in the next microtask after the state update, so there is
no window where `sessionStarted` is false but no session init is sent. Unlike
the server-side async-with-timeout TOCTOU pattern (learning 2026-03-20), the
React effect scheduler guarantees ordering.

## Acceptance Criteria

- [x] Opening an existing conversation URL and sending a message works without
      error (`apps/web-platform/lib/ws-client.ts`,
      `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`)
- [x] New conversations (`/dashboard/chat/new`) continue to work as before
      (deferred creation flow)
- [x] WebSocket reconnection after transient failure re-establishes the session
      (both new and existing conversations)
- [x] The `session_started` event is received before the user can send messages
      on an existing conversation
- [x] File attachments work on both new and existing conversations

## Test Scenarios

- Given a user is on an existing conversation page (UUID in URL), when the
  WebSocket connects and authenticates, then `resume_session` is sent with
  the conversation ID
- Given a user is on an existing conversation page, when they send a chat
  message (with or without attachments), then the message is accepted by the
  server (no "No active session" error)
- Given a user is on a new conversation page (`/dashboard/chat/new`), when the
  WebSocket connects and authenticates, then `start_session` is sent (deferred
  creation flow preserved)
- Given a user is on an existing conversation page and the WebSocket
  disconnects transiently, when it reconnects and authenticates, then
  `resume_session` is re-sent
- Given a user is on a new conversation page and the WebSocket disconnects
  transiently, when it reconnects and authenticates, then `start_session` is
  re-sent
- Given the server receives `resume_session` for a conversation not owned by
  the user, then the server responds with "Conversation not found" error

### Edge Cases (from learnings)

- Given a user is on an existing conversation and sends `resume_session`, when
  the server had a pending deferred conversation from a prior `start_session`,
  then the pending state is cleared before setting the conversation ID (per
  learning 2026-04-11 P1 bug: `session.pending = undefined` in `resume_session`)
- Given a user sends a follow-up message with attachments on a resumed
  conversation, when the agent-runner processes it, then attachment validation
  uses the correct `userId/conversationId` path prefix and downloads files to
  the workspace (no difference from the first-message flow)
- Given two tabs are open on the same conversation, when the second tab
  connects, then the first tab's socket receives close code 4002 (SUPERSEDED)
  and the second tab's `resume_session` binds correctly
- Given the WebSocket disconnects and reconnects within the 30-second grace
  period, when `resume_session` is re-sent, then the pending disconnect timer
  is cancelled and the agent session continues without replay

## Context

### Related PRs and Issues

- #1971 `fix(inbox): conversation state management, titles, and deferred creation`
  -- introduced deferred creation but did not add `resume_session` to the client
- #1975 `feat(attachments): chat file attachments` -- the scenario where the bug
  was first observed (PDF attachment on existing conversation)
- #1190 `fix: multi-turn conversation continuity` -- added `resume_session`
  protocol handler on the server side

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/lib/ws-client.ts` | Add `resumeSession` callback, export from hook |
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | Call `resumeSession` for existing conversations, reset `sessionStarted` on reconnect |

### Files for Reference (read-only)

| File | Why |
|------|-----|
| `apps/web-platform/server/ws-handler.ts` | Server-side `resume_session` handler (already implemented) |
| `apps/web-platform/lib/types.ts` | `WSMessage` type union includes `resume_session` |
| `apps/web-platform/test/ws-deferred-creation.test.ts` | Existing test patterns |
| `apps/web-platform/test/ws-protocol.test.ts` | Protocol validation tests |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- client-side WebSocket session management fix.

## References

### Code Paths

- Server-side `resume_session` handler: `apps/web-platform/server/ws-handler.ts:238-268`
- Server-side auth + session creation: `apps/web-platform/server/ws-handler.ts:570-624`
- Server-side disconnect grace period: `apps/web-platform/server/ws-handler.ts:640-667`
- Protocol type: `apps/web-platform/lib/types.ts:56`
- Client hook: `apps/web-platform/lib/ws-client.ts:80`
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:89-93`
- Agent runner `sendUserMessage`: `apps/web-platform/server/agent-runner.ts:1209-1407`

### Institutional Learnings Applied

- `2026-04-11-deferred-ws-conversation-creation-and-pending-state.md` --
  Dual-state session management (pending vs active); `resume_session` must
  clear pending state
- `2026-04-02-defensive-state-clear-on-useeffect-remount.md` -- Clear stale UI
  state before starting new connection lifecycle
- `2026-03-27-agent-sdk-session-resume-architecture.md` -- Hybrid resume
  architecture (SDK resume + message replay fallback)
- `2026-03-27-websocket-close-code-routing-reconnect-loop.md` -- Non-transient
  close codes and teardown pattern
- `2026-03-27-ws-session-race-abort-before-replace.md` -- Abort-before-replace
  pattern in session handlers
- `2026-03-20-websocket-first-message-auth-toctou-race.md` -- Async-with-timeout
  TOCTOU pattern (confirmed not applicable to React effect scheduler)
