---
title: "fix: Command Center chat sends message before session is established"
type: fix
date: 2026-04-03
deepened: 2026-04-03
---

# fix: Command Center chat sends message before session is established

## Enhancement Summary

**Deepened on:** 2026-04-03
**Sections enhanced:** 4 (Proposed Solution, Acceptance Criteria, Test Scenarios, Context)
**Research sources used:** React docs (Context7), 6 institutional learnings, 3 plan reviewers

### Key Improvements

1. Added reconnection reset for `sessionConfirmed` -- the original plan only reset on `startSession()`, missing the disconnect/reconnect path
2. Added `useEffect` cleanup pattern from React docs to prevent stale state on route changes and bfcache restore
3. Added edge case handling for `teardown()` path (non-transient close codes should clear `sessionConfirmed`)
4. Incorporated review feedback: kept `sessionStarted` naming to minimize diff noise in a bug fix

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

**Reconnection reset:** `sessionConfirmed` must also reset to `false` when the WebSocket reconnects. Inside the `connect()` callback, add `setSessionConfirmed(false)` before creating a new WebSocket. This prevents stale `true` values from a prior connection from triggering premature message sends after a transient disconnect. The `teardown()` helper (used for non-transient close codes like auth failure and supersession) should also clear `sessionConfirmed` since those paths permanently end the session.

```typescript
// In connect():
const connect = useCallback(async () => {
  if (!mountedRef.current) return;
  setSessionConfirmed(false); // Reset on every reconnection attempt
  // ... existing cleanup and WebSocket creation
}, [getWsUrlAndToken, teardown]);

// In teardown():
const teardown = useCallback(() => {
  mountedRef.current = false;
  clearTimeout(reconnectTimerRef.current);
  activeStreamsRef.current.clear();
  setSessionConfirmed(false); // Clear on permanent teardown
  if (wsRef.current) {
    wsRef.current.onclose = null;
    wsRef.current.close();
  }
}, []);
```

### Research Insights

**React effect sequencing pattern (from React docs):** When two effects have a sequential dependency (effect B depends on async completion of effect A), the correct pattern is to have effect B depend on a state variable that is set *by* effect A's async completion handler -- not a flag set optimistically when effect A fires. This is analogous to the "chained data fetching" pattern in React docs where the second `useEffect` depends on `planetId` being set by the first effect's fetch callback, not on the fetch being initiated.

**Defensive state clear on remount (from learning 2026-04-02):** The existing `useEffect` in `ws-client.ts` already clears `lastError` and `disconnectReason` at the top of the setup function (added in a prior bug fix for bfcache restore). The `sessionConfirmed` state should follow the same pattern -- clear it in the `useEffect` setup function alongside the other state resets.

**Fire-and-forget `.catch()` pattern (from learning 2026-03-20):** The `startAgentSession().catch()` in ws-handler.ts line 201 ensures that server-side errors during session creation are caught and sent to the client as error messages. This means if `createConversation()` fails, the client receives an `error` message (not `session_started`), so `sessionConfirmed` correctly stays `false` -- no additional error path handling needed on the client.

#### 2. Update chat page to use `sessionConfirmed` (`page.tsx`)

Keep the existing `sessionStarted` local state (tracks whether the client has sent `start_session`), but gate the initial message send on `sessionConfirmed` from the hook instead:

```typescript
// Effect 1 is unchanged — it still tracks whether we've requested a session:
const [sessionStarted, setSessionStarted] = useState(false);

useEffect(() => {
  if (status === "connected" && conversationId === "new" && !sessionStarted) {
    startSession(leaderId ?? undefined);
    setSessionStarted(true);
  }
}, [status, conversationId, leaderId, sessionStarted, startSession]);

// Effect 2 — the fix: gate on sessionConfirmed (server ack) instead of sessionStarted:
useEffect(() => {
  if (sessionConfirmed && msgParam && !initialMsgSent) {
    sendMessage(msgParam);
    setInitialMsgSent(true);
    router.replace(pathname, { scroll: false });
  }
}, [sessionConfirmed, msgParam, initialMsgSent, sendMessage, router, pathname]);
```

The key change: Effect 2 depends on `sessionConfirmed` (server acknowledgment) rather than `sessionStarted` (client-side flag set immediately after sending the request). The `status === "connected"` check is removed from Effect 2 because `sessionConfirmed` implies the connection is alive.

**Why keep `sessionStarted` naming (review feedback):** Renaming `sessionStarted` to `startRequested` would be a clarity improvement but adds unnecessary diff noise in a bug fix. The variable's role (preventing duplicate `startSession` calls) hasn't changed -- only the gating for the initial message send has changed.

### Why not fix on the server side?

The server-side guard (`if (!session.conversationId)`) is correct defense-in-depth. Removing it would allow messages to be silently dropped or misrouted if they arrive during the async gap. The client should not send messages before the session is confirmed -- this is a protocol sequencing issue.

## Acceptance Criteria

- [ ] Sending a message from the dashboard that navigates to `/dashboard/chat/new?msg=<text>` results in the message being delivered after the session is established, with no "No active session" error
- [ ] The `useWebSocket` hook exposes a `sessionConfirmed` boolean that is `true` only after receiving `session_started` from the server
- [ ] `sessionConfirmed` resets to `false` when `startSession()` is called (prevents stale state from a previous session)
- [ ] `sessionConfirmed` resets to `false` inside `connect()` on every reconnection attempt (prevents stale `true` from prior connection)
- [ ] `sessionConfirmed` resets to `false` inside `teardown()` on non-transient close codes (auth failure, superseded, idle timeout)
- [ ] Existing behavior is preserved: sessions without `?msg=` param work as before, manual `sendMessage` calls from the input field work as before
- [ ] Reconnection flows (transient disconnect, reconnect) do not break the new gating logic -- `sessionConfirmed` is `false` until the server re-confirms
- [ ] The `handleSend` function (manual chat input) is NOT gated on `sessionConfirmed` -- it relies on the existing `status === "connected"` check, since by the time a user manually types, the session is already confirmed
- [ ] `resume_session` server response also sets `sessionConfirmed` to `true` (the server sends `session_started` for both `start_session` and `resume_session`)

## Test Scenarios

### Core race condition fix

- Given a new conversation with `?msg=help with pricing`, when the page mounts and connects, then `startSession()` is called first, and `sendMessage("help with pricing")` is called only after `sessionConfirmed` becomes `true`
- Given a new conversation with `?msg=help with pricing`, when the page mounts and `sessionConfirmed` is `false`, then `sendMessage` is NOT called even though `sessionStarted` is `true`
- Given a new conversation without `?msg=`, when the page mounts and connects, then `startSession()` is called and no automatic `sendMessage` fires regardless of `sessionConfirmed` state

### Reconnection behavior

- Given a transient disconnect, when the WebSocket reconnects (new `connect()` call), then `sessionConfirmed` is `false` until the server sends a new `session_started`
- Given a non-transient close code (e.g., 4001 auth timeout), when `teardown()` runs, then `sessionConfirmed` is `false`
- Given a component remount (route change or bfcache restore), when the setup `useEffect` fires, then `sessionConfirmed` starts as `false`

### Session lifecycle

- Given rapid navigation between conversations, when `startSession` is called for a new conversation, then `sessionConfirmed` resets to `false` before the new session confirmation arrives
- Given a `session_started` message from the server, when the hook processes it, then `sessionConfirmed` becomes `true`
- Given a server error during `createConversation` (no `session_started` sent), when the hook receives an `error` message instead, then `sessionConfirmed` stays `false`

### Edge cases

- Given the `handleSend` function (manual chat input), when a user types and submits manually, then the send is gated on `status === "connected"` only (not `sessionConfirmed`), preserving existing behavior

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

- `2026-03-28-unapplied-migration-command-center-chat-failure.md` -- Previous occurrence of the same error message, caused by a different root cause (unapplied migration). The error message is the same but the cause is different (race condition vs. schema mismatch).
- `2026-03-27-ws-session-race-abort-before-replace.md` -- Related WebSocket session race condition, different vector (concurrent `start_session` calls), same module. Established the `abortActiveSession` pattern that runs synchronously before any `await`.
- `2026-04-02-defensive-state-clear-on-useeffect-remount.md` -- **Directly applicable.** Established the pattern of clearing stale UI state (`lastError`, `disconnectReason`) at the top of the connection setup `useEffect`. The `sessionConfirmed` state should follow this same pattern to handle bfcache restore and route navigation.
- `2026-03-20-websocket-first-message-auth-toctou-race.md` -- TOCTOU race between auth timeout and async token validation. Same module, same pattern class (state mutation after async boundary requires re-validation). Confirms the general principle: check state after every `await` before mutating shared state.
- `2026-03-27-websocket-close-code-routing-reconnect-loop.md` -- Established `NON_TRANSIENT_CLOSE_CODES` map and `teardown()` helper. The `teardown()` function is where `sessionConfirmed` must also reset to `false` on permanent close.
- `2026-03-20-fire-and-forget-promise-catch-handler.md` -- The `startAgentSession().catch()` pattern in ws-handler.ts ensures server-side errors are sent to the client as `error` messages (not `session_started`), so `sessionConfirmed` correctly stays `false` when session creation fails. No additional client-side error path handling needed.
- `2026-03-30-tdd-enforcement-gap-and-react-test-setup.md` -- Test setup reference: use `happy-dom` (not `jsdom`), `esbuild: { jsx: "automatic" }` (not `@vitejs/plugin-react`), and `environmentMatchGlobs` for `.tsx` files.

### References

- Existing test pattern: `chat-page.test.tsx` line 66-73 tests `msg` param handling but mocks hide the race
- The server-side `session_started` response is already sent (line 214) -- it just isn't consumed by the client for sequencing
- React docs: [Synchronizing with Effects](https://react.dev/learn/synchronizing-with-effects) -- the `ignore` flag cleanup pattern and chained data fetching example are analogous to this sequential effect dependency

### Review Feedback Applied

- **DHH reviewer:** Kept `sessionStarted` naming unchanged (minimizes diff noise in a bug fix)
- **Kieran reviewer:** Added reconnection reset gap -- `sessionConfirmed` resets in `connect()` and `teardown()`, not just `startSession()`
- **Kieran reviewer:** Noted `resume_session` path also sends `session_started` -- no additional handling needed since both paths set the same response type
- **Code simplicity reviewer:** Confirmed approach is minimal (~10 lines across two files), no YAGNI violations
