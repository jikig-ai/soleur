---
module: Web Platform
date: 2026-04-03
problem_type: runtime_error
component: frontend_stimulus
symptoms:
  - "Error: No active session. Send start_session first."
  - "CPO leader chip appears below error, indicating domain routing works but initial message was rejected"
  - "Only occurs when navigating to /dashboard/chat/new?msg=<text> with an initial message"
root_cause: async_timing
resolution_type: code_fix
severity: high
tags: [react, useeffect, race-condition, websocket, optimistic-state, server-acknowledgment]
synced_to: []
---

# Learning: React useEffect race condition — optimistic client flag vs server acknowledgment

## Problem

When starting a new Command Center session with an initial message via `?msg=` URL param, the user sees "Error: No active session. Send start_session first." The message is rejected because it arrives at the server before the session is ready.

Two React `useEffect` hooks fire in sequence during the same render cycle:

1. **Effect 1**: When `status === "connected"` and `conversationId === "new"`, calls `startSession()` and sets `sessionStarted = true` (client-side, optimistic)
2. **Effect 2**: When `sessionStarted && msgParam && !initialMsgSent`, calls `sendMessage(msgParam)`

The problem: `startSession()` sends a fire-and-forget WebSocket message. The server must `await createConversation()` (Supabase insert, ~50-200ms) before setting `session.conversationId`. Effect 2 fires before this async work completes.

```text
Client                          Server
  |--- start_session ------------>|
  |                               | createConversation() ... (async)
  |--- chat "sync my github" --->|
  |                               | session.conversationId === undefined
  |<-- error: No active session --|
```

## Investigation

- Confirmed the error appears only with `?msg=` param (programmatic send), never with manual typing (by that time the session is already confirmed)
- Server-side guard `if (!session.conversationId)` is correct defense-in-depth — the fix belongs on the client
- The `session_started` response from the server was already being sent but fell through to the `default` branch in the client's message handler — it was never consumed for sequencing

## Solution

Added `sessionConfirmed` boolean state to the `useWebSocket` hook that flips to `true` only when the server sends `{ type: "session_started" }`. Gated the initial message `useEffect` on `sessionConfirmed` instead of the optimistic `sessionStarted` flag.

**Key changes:**

- `ws-client.ts`: New `sessionConfirmed` state, explicit `case "session_started"` handler, resets in `teardown()`, `connect()`, setup `useEffect`, and `startSession()`
- `page.tsx`: Effect 2 condition changed from `sessionStarted && msgParam && !initialMsgSent && status === "connected"` to `sessionConfirmed && msgParam && !initialMsgSent`

The `status === "connected"` check was safely removed from Effect 2 because `sessionConfirmed` logically implies the connection is alive (you can't receive a server message on a dead connection).

## Key Insight

**When two React effects have a sequential dependency (effect B depends on async completion of effect A), gate effect B on a state variable set by effect A's async completion handler — not a flag set optimistically when effect A fires.** This is the "chained data fetching" pattern from React docs: the second effect depends on data from the first effect's callback, not on the fetch being initiated.

Optimistic flags are fine for UI indicators ("show spinner") but dangerous for protocol sequencing ("send message after session ready").

## Prevention

- When adding fire-and-forget WebSocket messages that have server-side async work, always check if downstream effects need the server's acknowledgment before proceeding
- The pattern: `client sends request` → `server does async work` → `server sends ack` → `client proceeds` — never skip the ack step for protocol-critical sequencing
- State resets must cover all lifecycle paths: teardown, reconnect, mount/remount, and new session start

## Session Errors

Session errors: none detected.

## Related

- `2026-03-27-ws-session-race-abort-before-replace.md` — Different WebSocket race condition vector (concurrent `start_session` calls), same module
- `2026-03-20-fire-and-forget-promise-catch-handler.md` — Server-side `.catch()` pattern ensures errors are sent as `error` messages, so `sessionConfirmed` correctly stays `false` on failure
- `2026-04-02-defensive-state-clear-on-useeffect-remount.md` — Established the pattern of clearing stale state at the top of setup `useEffect`
