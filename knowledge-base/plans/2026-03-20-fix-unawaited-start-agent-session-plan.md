---
title: "fix: add .catch() to unawaited startAgentSession() calls"
type: fix
date: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Root Cause, Proposed Fix, Acceptance Criteria, Test Scenarios, new Follow-Up section)
**Research sources:** Context7 TypeScript docs, web search (Node.js fire-and-forget patterns), codebase grep analysis, institutional learnings, pr-review-toolkit/silent-failure-hunter analysis

### Key Improvements
1. Confirmed production crash risk: Node 22 runtime + no `process.on('unhandledRejection')` handler = unhandled rejection terminates the server
2. Identified existing `.catch()` pattern at `ws-handler.ts:274` (`handleMessage`) that should be mirrored for consistency
3. Added `KeyInvalidError` handling to the `.catch()` handlers (the plan already mentioned this but the code examples were missing `errorCode`)
4. Identified follow-up: enable `@typescript-eslint/no-floating-promises` to prevent recurrence

### New Considerations Discovered
- The `ws-handler.ts` `start_session` case has a try/catch around `createConversation` but the `startAgentSession` call is outside it on line 130 -- if `startAgentSession` rejects, the try/catch does NOT help
- No ESLint or `@typescript-eslint/no-floating-promises` configured for web-platform -- static analysis would have caught this at authoring time
- The `handleMessage` function at `ws-handler.ts:274` already correctly uses `.catch()` for its own promise -- the `startAgentSession` call is the only inconsistency in the file

---

# fix: add .catch() to unawaited startAgentSession() calls

`startAgentSession()` is called fire-and-forget (no `await`, no `.catch()`) in two locations. If the async function throws before the internal try/catch engages (e.g., during `getUserApiKey()`, `createClient()`, or the Supabase query), the rejection is unhandled. The client receives no error indication, the conversation status is never set to `"failed"`, and Node.js terminates the process.

### Research Insights: Crash Severity

**Runtime confirmation:** The web-platform runs on Node 22 (`Dockerfile: FROM node:22-slim`). Since Node 15, unhandled promise rejections crash the process by default (`--unhandled-rejections=throw`). There is no `process.on('unhandledRejection')` handler anywhere in the server code. This means every unhandled rejection from `startAgentSession()` kills the entire server -- affecting all connected users, not just the one whose session failed.

**Industry standard (2025-2026):** The recommended pattern for fire-and-forget async calls is explicit `.catch()`:
```typescript
// Explicit fire-and-forget with .catch()
startAgentSession(userId, conversationId, leaderId).catch((err) => {
  console.error('[ws] startAgentSession error:', err);
  sendToClient(userId, { type: 'error', message: err.message });
});
```
This satisfies the `@typescript-eslint/no-floating-promises` rule and documents intent for future maintainers.

**Sources:**
- [Analyze Fire-and-Forget in NodeJS](https://medium.com/@onu.khatri/analyze-the-fire-forget-in-nodejs-7a60f78128ec)
- [typescript-eslint/no-floating-promises rule proposal](https://github.com/typescript-eslint/typescript-eslint/issues/6418)
- [Jake Archibald: The gotcha of unhandled promise rejections](https://jakearchibald.com/2023/unhandled-rejections/)

## Call Sites

| # | File | Line | Caller |
|---|------|------|--------|
| 1 | `apps/web-platform/server/ws-handler.ts` | 130 | `handleMessage` > `case "start_session"` |
| 2 | `apps/web-platform/server/agent-runner.ts` | 296 | `sendUserMessage()` |

Both call `startAgentSession(userId, conversationId, leaderId)` without awaiting or catching the returned promise.

## Root Cause

The calls are intentionally fire-and-forget -- the agent session streams results back via `sendToClient()` and the caller should not block on it. However, the fire-and-forget pattern requires a `.catch()` to handle early rejections that occur before `startAgentSession()`'s internal try/catch can engage.

The internal try/catch at line 106 of `agent-runner.ts` does handle errors during the session loop, but a rejection can escape if:

1. The promise microtask is rejected before the function body's try block runs (theoretically rare but possible with engine scheduling)
2. A future refactor adds throwing code before the try block (fragile -- silent breakage)

More importantly, `sendUserMessage()` at line 296 does not propagate errors to the WebSocket client at all -- it has no error handling wrapper around the `startAgentSession()` call.

### Research Insights: Existing Codebase Pattern

The codebase already uses the correct `.catch()` pattern in one place:

```typescript
// ws-handler.ts:274 -- existing correct pattern
ws.on("message", (data) => {
  handleMessage(userId, data.toString()).catch((err) => {
    console.error(`[ws] Unhandled error for user ${userId}:`, err);
    sendToClient(userId, { type: "error", message: "Internal server error" });
  });
});
```

The `startAgentSession()` calls are the only fire-and-forget promises in the server that lack `.catch()`. The fix aligns them with the established pattern.

### Research Insights: Institutional Learning

From `knowledge-base/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md`:
> When adding error classification to a message protocol, use typed error classes (`instanceof`) instead of string matching. Typed classes provide compile-time enforcement and survive refactoring.

This means the `.catch()` handlers must check `err instanceof KeyInvalidError` and attach `errorCode: "key_invalid"` -- not just forward the message string. The client-side handler at `ws-client.ts:178` depends on `errorCode === "key_invalid"` to redirect to `/setup-key`.

## Proposed Fix

Add `.catch()` handlers at both call sites that:

1. Send an `{ type: "error", message, errorCode? }` to the client via `sendToClient()`
2. Update conversation status to `"failed"` via `updateConversationStatus()`
3. Log the error server-side

### ws-handler.ts (line 130)

```typescript
// Boot the agent runner (async -- streams will flow via sendToClient)
startAgentSession(userId, conversationId, msg.leaderId).catch((err) => {
  console.error(`[ws] startAgentSession error:`, err);
  const message =
    err instanceof Error ? err.message : "Failed to start session";
  sendToClient(userId, {
    type: "error",
    message,
    errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined,
  });
});
```

**Note:** `KeyInvalidError` must be imported from `@/lib/types` in `ws-handler.ts`. The import already exists for `WSMessage` from `@/lib/types` so this is a one-line addition.

### agent-runner.ts (line 296, inside sendUserMessage)

```typescript
// Start a new agent turn with the user's message
startAgentSession(
  userId,
  conversationId,
  conv.domain_leader as DomainLeaderId,
).catch((err) => {
  console.error(
    `[agent] sendUserMessage session error for ${userId}/${conversationId}:`,
    err,
  );
  const message =
    err instanceof Error ? err.message : "Agent session failed";
  sendToClient(userId, {
    type: "error",
    message,
    errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined,
  });
  updateConversationStatus(conversationId, "failed").catch(() => {});
});
```

Note: `updateConversationStatus` itself gets a `.catch(() => {})` because it's a best-effort status update inside an already-failing path -- logging the primary error is sufficient. `KeyInvalidError` is already imported in `agent-runner.ts` (line 7).

### Research Insights: Edge Cases

**Double error delivery:** If `startAgentSession()` fails inside its own try/catch (line 257-268) AND the `.catch()` handler fires, the client could receive two error messages. Analysis shows this cannot happen: the internal catch block sends the error and then execution continues to the `finally` block -- the promise resolves (not rejects) from the internal catch. The `.catch()` only fires for rejections that escape the internal try/catch entirely.

**Race with abort:** If the session is aborted (line 96-97) and then the `.catch()` fires, the internal catch already guards against this with `if (!controller.signal.aborted)`. The external `.catch()` handler should not re-check abort status because it handles errors that escape the internal try/catch entirely -- those errors occur before `controller` is even checked.

**`sendToClient` after disconnect:** If the WebSocket disconnects before the error is sent, `sendToClient` no-ops silently (it checks `ws.readyState !== WebSocket.OPEN`). No additional guard needed.

## Why Not `await`?

The caller (`handleMessage`) should not block on the agent session. The session can run for minutes (up to 50 turns). The fire-and-forget pattern is correct -- the missing piece is only the `.catch()` handler for early failures.

## Acceptance Criteria

- [x] `startAgentSession()` call in `ws-handler.ts` line 130 has a `.catch()` that sends error to client (`apps/web-platform/server/ws-handler.ts`)
- [x] `startAgentSession()` call in `agent-runner.ts` line 296 has a `.catch()` that sends error to client and updates conversation status (`apps/web-platform/server/agent-runner.ts`)
- [x] Both `.catch()` handlers attach `errorCode: "key_invalid"` when error is `KeyInvalidError` instance (consistent with existing error handling in `startAgentSession`'s internal catch block and client-side redirect at `ws-client.ts:178`)
- [x] `KeyInvalidError` is imported in `ws-handler.ts` from `@/lib/types`
- [x] Existing tests pass (`bun test` in `apps/web-platform/`)
- [x] TypeScript compiles cleanly (`bunx tsc --noEmit` in `apps/web-platform/`) (pre-existing module resolution errors only — no new errors from this change)

## Test Scenarios

- Given a user with no API key, when `start_session` is received, then the client receives `{ type: "error", message: "No valid API key found...", errorCode: "key_invalid" }` (not an unhandled rejection that crashes the server)
- Given a user whose workspace is not provisioned, when `sendUserMessage` triggers a new agent turn, then the client receives `{ type: "error", message: "Workspace not provisioned" }` and conversation status is set to `"failed"`
- Given an active session running normally, when the agent completes, then behavior is unchanged (the `.catch()` never fires because the internal try/catch resolves the promise)
- Given a user whose WebSocket disconnects before the error is sent, when `startAgentSession` fails, then `sendToClient` no-ops silently and the server does not crash

### Research Insights: Test Limitations

The existing test file (`apps/web-platform/test/ws-protocol.test.ts`) tests message parsing and type discrimination in isolation. It cannot test the actual `.catch()` wiring without mocking the Supabase client and Agent SDK (which have module-level side effects per learning `2026-03-18-typed-error-codes-websocket-key-invalidation.md`). The acceptance criteria "existing tests pass" verifies no regression; verifying the fix requires either integration tests or manual testing with a missing API key.

## Context

- Discovered during code review of PR #721
- Pre-existing since the MVP commit
- Related learning: `knowledge-base/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md`

## Follow-Up Recommendations

### 1. Enable `@typescript-eslint/no-floating-promises` (separate issue)

The web-platform app has no ESLint configuration. Adding `@typescript-eslint/no-floating-promises` would catch this class of bug at authoring time. This is a larger effort (installing ESLint + typescript-eslint, configuring tsconfig for linting) and should be tracked as a separate issue.

### 2. Consider `process.on('unhandledRejection')` as defense-in-depth (separate issue)

Adding a global handler in `server/index.ts` as a last-resort safety net would log the error and prevent process termination for any future unhandled rejections. This is defense-in-depth -- the `.catch()` fix is the correct solution, but a global handler catches anything that slips through.

```typescript
process.on('unhandledRejection', (reason, promise) => {
  console.error('[server] Unhandled rejection at:', promise, 'reason:', reason);
  // Do NOT re-throw -- let the process continue serving other users
});
```

## References

- Issue: #727
- File: `apps/web-platform/server/agent-runner.ts:296`
- File: `apps/web-platform/server/ws-handler.ts:130`
- Existing pattern: `apps/web-platform/server/ws-handler.ts:274` (`.catch()` on `handleMessage`)
- Runtime: `apps/web-platform/Dockerfile` (Node 22, `--unhandled-rejections=throw` by default)
- Client handler: `apps/web-platform/lib/ws-client.ts:178` (key_invalid redirect)
- Types: `apps/web-platform/lib/types.ts` (KeyInvalidError, WSErrorCode)
