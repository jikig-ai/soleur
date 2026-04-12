---
title: "fix: send resume_session when opening existing conversations"
type: fix
date: 2026-04-12
---

# fix: send resume\_session when opening existing conversations

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

## Acceptance Criteria

- [ ] Opening an existing conversation URL and sending a message works without
      error (`apps/web-platform/lib/ws-client.ts`,
      `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`)
- [ ] New conversations (`/dashboard/chat/new`) continue to work as before
      (deferred creation flow)
- [ ] WebSocket reconnection after transient failure re-establishes the session
      (both new and existing conversations)
- [ ] The `session_started` event is received before the user can send messages
      on an existing conversation
- [ ] File attachments work on both new and existing conversations

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

- Server-side `resume_session` handler: `apps/web-platform/server/ws-handler.ts:238-268`
- Protocol type: `apps/web-platform/lib/types.ts:56`
- Client hook: `apps/web-platform/lib/ws-client.ts:80`
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:89-93`
