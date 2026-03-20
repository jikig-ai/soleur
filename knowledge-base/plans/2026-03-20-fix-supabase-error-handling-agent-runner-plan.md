---
title: "fix: check Supabase error return values in saveMessage and updateConversationStatus"
type: fix
date: 2026-03-20
---

# fix: check Supabase error return values in saveMessage and updateConversationStatus

## Overview

`saveMessage()` and `updateConversationStatus()` in `apps/web-platform/server/agent-runner.ts` call the Supabase JS client without checking the `{ error }` return value. The Supabase JS client does **not** throw on failed queries -- it returns `{ data, error }`. This means insert/update failures are completely silent: messages are lost without any indication, and conversation statuses get stuck in stale states.

Both functions are pre-existing bugs discovered during code review of PR #830.

Closes #838, Closes #839.

## Problem Statement

### saveMessage (issue #838, lines 61-73)

```typescript
// Current -- error silently ignored
await supabase.from("messages").insert({
  id: randomUUID(),
  conversation_id: conversationId,
  role,
  content,
  tool_calls: toolCalls || null,
});
```

If the insert fails (constraint violation, DB down, RLS policy), the user sees the streamed response but it is never persisted. On reload, the message is gone.

### updateConversationStatus (issue #839, lines 76-83)

```typescript
// Current -- error silently ignored
await supabase
  .from("conversations")
  .update({ status, last_active: new Date().toISOString() })
  .eq("id", conversationId);
```

Called in 5 places with statuses: `waiting_for_user`, `active`, `completed`, `failed` (x2). Failed updates leave conversations in stale states, breaking UI indicators and potentially preventing new sessions.

## Proposed Solution

Add `const { error }` destructuring and throw on error in both functions, matching the pattern already established in:

- `createConversation()` in `ws-handler.ts` (lines 63-73) -- the correct reference implementation
- `getUserApiKey()` in `agent-runner.ts` (lines 38-49) -- already checks `error`

### saveMessage fix (`apps/web-platform/server/agent-runner.ts`)

```typescript
async function saveMessage(
  conversationId: string,
  role: "user" | "assistant",
  content: string,
  toolCalls?: unknown,
) {
  const { error } = await supabase.from("messages").insert({
    id: randomUUID(),
    conversation_id: conversationId,
    role,
    content,
    tool_calls: toolCalls || null,
  });

  if (error) {
    throw new Error(`Failed to save message: ${error.message}`);
  }
}
```

### updateConversationStatus fix (`apps/web-platform/server/agent-runner.ts`)

```typescript
async function updateConversationStatus(
  conversationId: string,
  status: string,
) {
  const { error } = await supabase
    .from("conversations")
    .update({ status, last_active: new Date().toISOString() })
    .eq("id", conversationId);

  if (error) {
    throw new Error(`Failed to update conversation status: ${error.message}`);
  }
}
```

## Error Propagation Analysis

Both functions are `async` and callers already handle errors correctly:

| Call site | Function | Status | Error handling |
|-----------|----------|--------|----------------|
| Line 188 | `updateConversationStatus` | `waiting_for_user` | Inside `canUseTool` callback, awaited. Errors propagate to the `startAgentSession` try/catch on line 258 |
| Line 195 | `updateConversationStatus` | `active` | Same context as above |
| Line 231 | `saveMessage` | assistant response | Inside `for await` loop, awaited. Errors propagate to the try/catch on line 258 |
| Line 234 | `updateConversationStatus` | `completed` | Same context as above |
| Line 267 | `updateConversationStatus` | `failed` | Inside the catch block itself. If this throws, it becomes an unhandled rejection from the catch. Needs a nested try/catch or `.catch()` |
| Line 283 | `saveMessage` | user message | In `sendUserMessage`, awaited. Errors propagate to caller (ws-handler chat case, which has try/catch) |
| Line 311 | `updateConversationStatus` | `failed` | Inside `.catch()` handler in `sendUserMessage`. Already has its own `.catch()` with logging -- correct |

**Critical edge case (line 267):** The `updateConversationStatus(conversationId, "failed")` on line 267 is inside `startAgentSession`'s catch block. If this newly-throwing function fails here, the error escapes the catch and becomes an unhandled rejection. This call site needs a nested `.catch()` or try/catch:

```typescript
// Line 267 -- must not let status update failure escape the catch block
await updateConversationStatus(conversationId, "failed").catch(
  (statusErr) => {
    console.error(
      `[agent] Failed to mark conversation ${conversationId} as failed:`,
      statusErr,
    );
  },
);
```

This matches the defensive pattern already used in `sendUserMessage` at line 311.

## Acceptance Criteria

- [ ] `saveMessage()` destructures `{ error }` from the Supabase insert and throws on error
- [ ] `updateConversationStatus()` destructures `{ error }` from the Supabase update and throws on error
- [ ] The `updateConversationStatus("failed")` call inside `startAgentSession`'s catch block (line 267) is wrapped with `.catch()` to prevent unhandled rejection
- [ ] Error messages include the Supabase error detail (e.g., `Failed to save message: <error.message>`) for server-side logging; these are already sanitized before reaching the client by `sanitizeErrorForClient()`
- [ ] Existing tests pass (`bun test` in `apps/web-platform/`)

## Test Scenarios

- Given a Supabase insert failure in `saveMessage`, when the function is called, then it throws an Error containing the Supabase error message
- Given a Supabase update failure in `updateConversationStatus`, when the function is called, then it throws an Error containing the Supabase error message
- Given a successful Supabase insert in `saveMessage`, when the function is called, then it resolves without throwing
- Given a successful Supabase update in `updateConversationStatus`, when the function is called, then it resolves without throwing
- Given the `updateConversationStatus("failed")` call in the catch block throws, when a session error occurs, then the status error is logged but does not become an unhandled rejection
- Given `saveMessage` throws during `sendUserMessage`, when the error propagates, then the client receives a sanitized error message (not raw Supabase details)

## Context

- The Supabase JS client returns `{ data, error }` and does **not** throw on failures. This is a well-known footgun documented in Supabase's own guides.
- The existing `createConversation()` in `ws-handler.ts` and `getUserApiKey()` in `agent-runner.ts` already follow the correct pattern. These two functions were missed during MVP development.
- The `error-sanitizer.ts` module (added in PR #829) already handles unknown errors with a generic fallback, so the interpolated error messages (`Failed to save message: ...`) will never leak to the client.
- Two additional Supabase calls in `agent-runner.ts` (lines 116 and 287) also skip `error` destructuring but are partially defended by null-data checks. These are out of scope for this PR but should be tracked separately.

## References

- Issue #838: `saveMessage` ignores Supabase error return value
- Issue #839: `updateConversationStatus` ignores Supabase error return value
- `apps/web-platform/server/agent-runner.ts` (lines 60-84, 267, 283, 311)
- `apps/web-platform/server/ws-handler.ts` (lines 57-76) -- correct pattern reference
- `apps/web-platform/server/error-sanitizer.ts` -- sanitization layer
- Learning: `knowledge-base/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md`
- Learning: `knowledge-base/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md`
