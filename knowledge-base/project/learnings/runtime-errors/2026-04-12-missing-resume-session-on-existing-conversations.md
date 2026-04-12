---
module: web-platform
date: 2026-04-12
problem_type: runtime_error
component: websocket_client
symptoms:
  - "Error: No active session. Send start_session first."
  - "Messages fail on existing conversation pages after page refresh or navigation"
root_cause: missing_protocol_message
severity: high
tags: [websocket, session-management, resume-session, reconnection]
synced_to: []
---

# Missing resume_session on Existing Conversations

## Problem

When a user navigated to an existing conversation page (URL contains a real
UUID like `/dashboard/chat/fc105c6a-...`), the WebSocket client authenticated
but never sent a `resume_session` message. The server-side session had neither
`conversationId` nor `pending` set, so any chat message was rejected with:

> Error: No active session. Send start_session first.

The bug affected all messages on returning conversations, not just attachments.
It was first noticed when a user tried to send a PDF attachment on a previously
working conversation.

## Investigation

1. **Checked server-side handler** -- `resume_session` handler existed at
   `ws-handler.ts:238-268` and was fully implemented (ownership check, abort
   prior session, set conversationId).
2. **Checked client-side hook** -- `useWebSocket` had `startSession` but no
   `resumeSession` callback. The `resume_session` WSMessage type was defined
   in `types.ts:56` but never sent by the client.
3. **Checked page component** -- Session init `useEffect` only fired when
   `conversationId === "new"`. Existing conversations (UUID in URL) were
   completely skipped.
4. **Root cause confirmed** -- The `resume_session` protocol was added in
   #1190 for multi-turn continuity but was never wired into the client page
   component. The deferred creation refactor (#1971) didn't add it either.

## Solution

Three changes across two files:

### 1. Added `resumeSession` to `useWebSocket` hook (`ws-client.ts`)

```typescript
const resumeSession = useCallback(
  (targetConversationId: string) => {
    setSessionConfirmed(false);
    send({ type: "resume_session", conversationId: targetConversationId });
  },
  [send],
);
```

### 2. Updated session init `useEffect` in `page.tsx`

```typescript
useEffect(() => {
  if (status !== "connected" || sessionStarted) return;

  if (conversationId === "new") {
    if (!contextLoading) {
      startSession(leaderId ?? undefined, kbContext);
      setSessionStarted(true);
    }
  } else {
    resumeSession(conversationId);
    setSessionStarted(true);
  }
}, [status, conversationId, leaderId, sessionStarted, startSession, resumeSession, contextLoading, kbContext]);
```

### 3. Added reconnection reset `useEffect`

```typescript
useEffect(() => {
  if (status === "reconnecting") {
    setSessionStarted(false);
  }
}, [status]);
```

Server creates a blank `ClientSession` on every new auth (`ws-handler.ts:603`),
so the client MUST re-send session init after every reconnection.

## Key Insight

When a WebSocket protocol defines both `start_session` and `resume_session`
messages, both paths must be wired end-to-end (server handler AND client
caller). A server handler without a client caller is dead code that silently
breaks the feature it was meant to support. The gap went unnoticed because
conversations that started as "new" within the same WebSocket connection worked
fine -- the bug only manifested on page refresh or navigation to an existing
conversation URL.

## Session Errors

1. **error-states.test.tsx mock broke after adding resumeSession** -- The test
   file's `useWebSocket` mock didn't include the new `resumeSession` function,
   causing 4 test failures with `TypeError: resumeSession is not a function`.
   Recovery: added `resumeSession`, `sessionConfirmed`, and `usageData` to the
   mock. **Prevention:** When adding new return values to a React hook, grep
   for all test files that mock that hook and update them in the same commit.

2. **Dev server failed to start for browser QA** -- Supabase env vars
   (`SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_URL`) missing from Doppler `dev`
   config. The server crashed on startup. Recovery: skipped browser QA, relied
   on unit test coverage. **Prevention:** Add Supabase env vars to Doppler dev
   config or create a QA-specific config with all required vars.

## Prevention

- When adding a new protocol message handler on the server, always verify the
  client sends that message. Search for `send({ type: "new_message_type"` in
  client code.
- When refactoring session management (e.g., deferred creation), audit all
  session initialization paths: new conversations, existing conversations,
  and reconnection after transient failure.
- After adding new fields to a hook's return type, run the full test suite
  before committing -- mocks in other test files may need the same field.

## Cross-References

- `2026-04-11-deferred-ws-conversation-creation-and-pending-state.md` --
  Deferred creation flow that introduced the session init useEffect
- `2026-03-27-ws-session-race-abort-before-replace.md` -- Abort-before-replace
  pattern used in resume_session handler
- `2026-03-27-agent-sdk-session-resume-architecture.md` -- Resume architecture
  design decisions

## Tags

category: runtime-errors
module: web-platform
