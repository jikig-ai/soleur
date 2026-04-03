---
title: "fix: Command Center chat sends message before session is established"
type: fix
date: 2026-04-03
---

# fix: Command Center chat sends message before session is established

## Overview

When starting a new session from the Command Center dashboard with an initial message (e.g., "can we sync my github project?"), the user sees "Error: No active session. Send start_session first." instead of the message being processed. The CPO leader chip appears below the error, indicating domain routing eventually works but the initial message arrives at the server before the session is ready.

## Problem Statement

The chat page (`app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`) has two `useEffect` hooks that fire in sequence during the same React render cycle:

1. **Effect 1 (line 51)**: When `status === "connected"` and `conversationId === "new"`, calls `startSession()` and immediately sets `sessionStarted = true`.

2. **Effect 2 (line 59)**: When `sessionStarted && msgParam && !initialMsgSent`, calls `sendMessage(msgParam)`.

The problem is that `startSession()` sends a fire-and-forget `{ type: "start_session" }` WebSocket message. The server-side handler (`ws-handler.ts:178-222`) must await `createConversation()` (a Supabase insert) before setting `session.conversationId`. Meanwhile, the client has already set `sessionStarted = true` locally and the second effect fires `sendMessage()`, which sends `{ type: "chat", content: "..." }`.

When the server receives the `chat` message, `session.conversationId` is still `undefined` because `createConversation()` hasn't resolved yet, so the guard on line 292-296 fires: "No active session. Send start_session first."

The CPO leader chip appears because the `start_session` eventually completes and the agent begins processing -- but the user's initial message was already rejected.

### Sequence diagram

```text
Client                          Server
  |--- start_session ------------>|
  |                               | createConversation() ... (async, ~50-200ms)
  |--- chat "sync my github" --->|
  |                               | session.conversationId === undefined
  |<-- error: No active session --|
  |                               | createConversation() resolves
  |                               | session.conversationId = uuid
  |<-- session_started -----------|
  |                               | agent boots, domain routing works
  |<-- stream_start (CPO) -------|
```

## Proposed Solution

Track `session_started` confirmation from the server in the WebSocket hook, and gate the initial message send on that confirmation rather than the client-side `sessionStarted` flag.

### Changes

#### 1. Add `sessionConfirmed` state to `useWebSocket` hook (`lib/ws-client.ts`)

Add a new boolean state `sessionConfirmed` that flips to `true` only when the server sends back `{ type: "session_started" }`. Expose it in the return value.

```typescript
// In useWebSocket:
const [sessionConfirmed, setSessionConfirmed] = useState(false);

// In the onmessage handler, session_started case (currently in the default branch):
case "session_started": {
  setSessionConfirmed(true);
  break;
}

// Reset on new session start:
const startSession = useCallback((leaderId?, context?) => {
  setSessionConfirmed(false);
  send({ type: "start_session", leaderId, context });
}, [send]);
```

Currently, `session_started` falls through to the `default` branch (line 273 comment says "session_started, chat -- no UI message needed"). This change adds explicit handling.

#### 2. Update chat page to use `sessionConfirmed` (`page.tsx`)

Replace the `sessionStarted` local state with the server-confirmed signal:

```typescript
// Before (broken):
const [sessionStarted, setSessionStarted] = useState(false);

useEffect(() => {
  if (status === "connected" && conversationId === "new" && !sessionStarted) {
    startSession(leaderId ?? undefined);
    setSessionStarted(true);
  }
}, [status, conversationId, leaderId, sessionStarted, startSession]);

useEffect(() => {
  if (sessionStarted && msgParam && !initialMsgSent && status === "connected") {
    sendMessage(msgParam);
    setInitialMsgSent(true);
    router.replace(pathname, { scroll: false });
  }
}, [sessionStarted, msgParam, initialMsgSent, status, ...]);

// After (fixed):
const [startRequested, setStartRequested] = useState(false);

useEffect(() => {
  if (status === "connected" && conversationId === "new" && !startRequested) {
    startSession(leaderId ?? undefined);
    setStartRequested(true);
  }
}, [status, conversationId, leaderId, startRequested, startSession]);

useEffect(() => {
  if (sessionConfirmed && msgParam && !initialMsgSent) {
    sendMessage(msgParam);
    setInitialMsgSent(true);
    router.replace(pathname, { scroll: false });
  }
}, [sessionConfirmed, msgParam, initialMsgSent, sendMessage, router, pathname]);
```

The key change: `sendMessage` is gated on `sessionConfirmed` (server acknowledgment) rather than `sessionStarted` (client-side flag set immediately after sending the request).

### Why not fix on the server side?

The server-side guard (`if (!session.conversationId)`) is correct defense-in-depth. Removing it would allow messages to be silently dropped or misrouted if they arrive during the async gap. The client should not send messages before the session is confirmed -- this is a protocol sequencing issue.

## Acceptance Criteria

- [ ] Sending a message from the dashboard that navigates to `/dashboard/chat/new?msg=<text>` results in the message being delivered after the session is established, with no "No active session" error
- [ ] The `useWebSocket` hook exposes a `sessionConfirmed` boolean that is `true` only after receiving `session_started` from the server
- [ ] `sessionConfirmed` resets to `false` when `startSession()` is called (prevents stale state from a previous session)
- [ ] Existing behavior is preserved: sessions without `?msg=` param work as before, manual `sendMessage` calls from the input field work as before
- [ ] Reconnection flows (transient disconnect, reconnect) do not break the new gating logic
- [ ] The `handleSend` function (manual chat input) is NOT gated on `sessionConfirmed` -- it relies on the existing `status === "connected"` check, since by the time a user manually types, the session is already confirmed

## Test Scenarios

- Given a new conversation with `?msg=help with pricing`, when the page mounts and connects, then `startSession()` is called first, and `sendMessage("help with pricing")` is called only after `session_started` is received from the server
- Given a new conversation without `?msg=`, when the page mounts and connects, then `startSession()` is called and no automatic `sendMessage` fires
- Given a reconnection after disconnect, when status transitions to `connected`, then `sessionConfirmed` reflects the actual server state (false until re-confirmed)
- Given rapid navigation between conversations, when `startSession` is called for a new conversation, then `sessionConfirmed` resets to false before the new session confirmation arrives

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is a client-side WebSocket protocol sequencing fix with no user-facing page changes, no business logic changes, and no infrastructure impact.

## Context

### Related files

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- chat page with the race condition
- `apps/web-platform/lib/ws-client.ts` -- WebSocket hook that needs `sessionConfirmed` state
- `apps/web-platform/server/ws-handler.ts` -- server-side handler (no changes needed, the guard is correct)
- `apps/web-platform/test/chat-page.test.tsx` -- existing tests to update
- `apps/web-platform/test/ws-protocol.test.ts` -- protocol tests

### Related learnings

- `knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md` -- previous occurrence of the same error message, caused by a different root cause (unapplied migration). The error message is the same but the cause is different (race condition vs. schema mismatch).
- `knowledge-base/project/learnings/2026-03-27-ws-session-race-abort-before-replace.md` -- related WebSocket session race condition, different vector (concurrent `start_session` calls), same module.

### References

- Existing test pattern: `chat-page.test.tsx` line 66-73 tests `msg` param handling but mocks hide the race
- The server-side `session_started` response is already sent (line 214) -- it just isn't consumed by the client for sequencing
