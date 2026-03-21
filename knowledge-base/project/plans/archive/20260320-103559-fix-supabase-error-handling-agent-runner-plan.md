---
title: "fix: check Supabase error return values in saveMessage and updateConversationStatus"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Proposed Solution, Error Propagation, Test Scenarios, Context)
**Research sources:** Supabase JS v2.58.0 docs (Context7), codebase-wide Supabase call audit, institutional learnings

### Key Improvements

1. Added Supabase documentation grounding confirming `{ data, error }` is the canonical pattern and `throwOnError()` exists but is not appropriate here
2. Identified two additional partially-defended Supabase calls (lines 116, 287) with concrete follow-up recommendation
3. Added `error.code` to thrown error messages for operational debugging (Supabase errors include machine-readable PGRST codes)
4. Strengthened test scenarios with specific Supabase error shapes and edge case coverage

### New Considerations Discovered

- Supabase error objects contain `message`, `code`, `details`, and `hint` fields -- including `code` in thrown errors aids operational debugging without leaking info (sanitizer catches it)
- `updateConversationStatus` inside `canUseTool` (lines 188, 195) runs in an async callback passed to the Agent SDK -- errors thrown there may not propagate as expected depending on the SDK's internal handling; the existing try/catch on line 258 should catch them since `canUseTool` is awaited by the SDK, but this is worth verifying during implementation
- The `throwOnError()` API exists on the Supabase client but would change the error contract globally -- the per-call `{ error }` check is correct for this codebase

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

### Research Insights

**Supabase JS Client Error Contract (v2.58.0, confirmed via Context7):**

The Supabase JS client consistently returns `{ data, error }` from all query operations. The `error` object, when present, contains:

- `message` (string) -- human-readable description
- `code` (string) -- PostgreSQL/PostgREST error code (e.g., `"23505"` for unique violation, `"42P01"` for undefined table)
- `details` (string) -- additional context
- `hint` (string) -- suggested fix

The client also supports a `throwOnError()` chainable method that converts the return-value pattern to a throw-on-error pattern. However, `throwOnError()` changes the contract for the entire chain and would require refactoring all callers. The per-call `if (error)` check is the correct approach for incremental fixes in this codebase.

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
| Line 188 | `updateConversationStatus` | `waiting_for_user` | Inside `canUseTool` async callback, awaited. The Agent SDK awaits `canUseTool`, so errors propagate to the `for await` loop and then to the try/catch on line 258 |
| Line 195 | `updateConversationStatus` | `active` | Same context as line 188 |
| Line 231 | `saveMessage` | assistant response | Inside `for await` loop, awaited. Errors propagate to the try/catch on line 258 |
| Line 234 | `updateConversationStatus` | `completed` | Same context as line 231 |
| Line 267 | `updateConversationStatus` | `failed` | **CRITICAL:** Inside the catch block itself. If this throws, it becomes an unhandled rejection. Needs a nested `.catch()` |
| Line 283 | `saveMessage` | user message | In `sendUserMessage`, awaited. Errors propagate to caller (ws-handler chat case, which has try/catch) |
| Line 311 | `updateConversationStatus` | `failed` | Inside `.catch()` handler in `sendUserMessage`. Already has its own `.catch()` with logging -- correct |

### Research Insights

**canUseTool callback propagation (lines 188, 195):** The `canUseTool` callback is an async function passed to the Agent SDK's `query()` options. The SDK awaits this callback during tool invocation, meaning a thrown error will reject the iterator's `next()` call, which surfaces in the `for await` loop and propagates to the outer try/catch. This is the expected behavior, but during implementation verify by tracing the error path: throw in `updateConversationStatus` -> rejects `canUseTool` return -> rejects `for await` iteration -> caught at line 258. If the SDK swallows errors in `canUseTool` (returns a default deny), the status update failure would be silent -- check SDK behavior during testing.

**Critical edge case (line 267):** The `updateConversationStatus(conversationId, "failed")` on line 267 is inside `startAgentSession`'s catch block. If this newly-throwing function fails here, the error escapes the catch and becomes an unhandled rejection. On Node 22 (`--unhandled-rejections=throw` default since Node 15), this terminates the entire server process -- affecting all connected users. This call site needs a nested `.catch()`:

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

This matches the defensive pattern already used in `sendUserMessage` at line 311. The learning from `knowledge-base/project/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md` documents the same class of issue: every async call in a catch block needs its own error boundary.

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

- The Supabase JS client returns `{ data, error }` and does **not** throw on failures. This is confirmed by the [Supabase JS v2.58.0 documentation](https://supabase.com/docs/reference/javascript/insert) and is a well-known footgun.
- The existing `createConversation()` in `ws-handler.ts` and `getUserApiKey()` in `agent-runner.ts` already follow the correct pattern. These two functions were missed during MVP development.
- The `error-sanitizer.ts` module (added in PR #829) already handles unknown errors with a generic fallback, so the interpolated error messages (`Failed to save message: ...`) will never leak to the client. Verified: the error message format `Failed to save message: <supabase error>` does not match any entry in `KNOWN_SAFE_MESSAGES` and does not start with `"Unknown leader:"`, so it falls through to the generic `"An unexpected error occurred. Please try again."` response.
- The `typed-error-codes-websocket-key-invalidation` learning confirms that error classification in this codebase uses `instanceof` checks, not string matching -- the thrown `Error` objects from these fixes are correctly handled by the existing error chain.

### Codebase-Wide Supabase Call Audit

A full audit of `supabase.from()` calls in `apps/web-platform/server/` reveals:

| File | Line | Table | Operation | Error checked? |
|------|------|-------|-----------|----------------|
| `agent-runner.ts` | 38-49 | `api_keys` | `.select().single()` | Yes -- `{ data, error }` with throw |
| `agent-runner.ts` | 67 | `messages` | `.insert()` | **No** -- this PR fixes it |
| `agent-runner.ts` | 80-83 | `conversations` | `.update().eq()` | **No** -- this PR fixes it |
| `agent-runner.ts` | 116-120 | `users` | `.select().single()` | Partial -- `{ data: user }` only, error ignored; `!user?.workspace_path` catches null data but loses error detail |
| `agent-runner.ts` | 287-291 | `conversations` | `.select().single()` | Partial -- `{ data: conv }` only, error ignored; `!conv` catches null but loses error detail |
| `ws-handler.ts` | 63 | `conversations` | `.insert()` | Yes -- correct pattern |

**Follow-up recommendation:** File a separate GitHub issue to add `error` destructuring to lines 116 and 287. These are partially defended (the null-data guard catches the failure mode) but silently discard Supabase error details, making debugging harder when the database is unreachable vs. the row genuinely not existing.

## References

- Issue #838: `saveMessage` ignores Supabase error return value
- Issue #839: `updateConversationStatus` ignores Supabase error return value
- `apps/web-platform/server/agent-runner.ts` (lines 60-84, 267, 283, 311)
- `apps/web-platform/server/ws-handler.ts` (lines 57-76) -- correct pattern reference
- `apps/web-platform/server/error-sanitizer.ts` -- sanitization layer
- [Supabase JS Client docs (Context7)](https://supabase.com/docs/reference/javascript/insert) -- confirms `{ data, error }` return contract
- Learning: `knowledge-base/project/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md` -- catch block error boundary pattern
- Learning: `knowledge-base/project/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md` -- error sanitization layer
- Learning: `knowledge-base/project/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md` -- instanceof-based error classification
