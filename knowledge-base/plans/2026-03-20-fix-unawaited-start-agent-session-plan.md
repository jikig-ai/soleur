---
title: "fix: add .catch() to unawaited startAgentSession() calls"
type: fix
date: 2026-03-20
---

# fix: add .catch() to unawaited startAgentSession() calls

`startAgentSession()` is called fire-and-forget (no `await`, no `.catch()`) in two locations. If the async function throws before the internal try/catch engages (e.g., during `getUserApiKey()`, `createClient()`, or the Supabase query), the rejection is unhandled. The client receives no error indication, the conversation status is never set to `"failed"`, and Node.js logs an `UnhandledPromiseRejection` warning (which crashes the process in Node 15+ with `--unhandled-rejections=throw`).

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

## Proposed Fix

Add `.catch()` handlers at both call sites that:

1. Send an `{ type: "error", message }` to the client via `sendToClient()`
2. Update conversation status to `"failed"` via `updateConversationStatus()`
3. Log the error server-side

### ws-handler.ts (line 130)

```typescript
// Boot the agent runner (async -- streams will flow via sendToClient)
startAgentSession(userId, conversationId, msg.leaderId).catch((err) => {
  console.error(`[ws] startAgentSession error:`, err);
  const message =
    err instanceof Error ? err.message : "Failed to start session";
  sendToClient(userId, { type: "error", message });
});
```

### agent-runner.ts (line 296, inside sendUserMessage)

```typescript
startAgentSession(
  userId,
  conversationId,
  conv.domain_leader as DomainLeaderId,
).catch((err) => {
  console.error(`[agent] sendUserMessage session error for ${userId}/${conversationId}:`, err);
  const message =
    err instanceof Error ? err.message : "Agent session failed";
  sendToClient(userId, { type: "error", message });
  updateConversationStatus(conversationId, "failed").catch(() => {});
});
```

Note: `updateConversationStatus` itself gets a `.catch(() => {})` because it's a best-effort status update inside an already-failing path -- logging the primary error is sufficient.

## Why Not `await`?

The caller (`handleMessage`) should not block on the agent session. The session can run for minutes (up to 50 turns). The fire-and-forget pattern is correct -- the missing piece is only the `.catch()` handler for early failures.

## Acceptance Criteria

- [ ] `startAgentSession()` call in `ws-handler.ts` line 130 has a `.catch()` that sends error to client
- [ ] `startAgentSession()` call in `agent-runner.ts` line 296 has a `.catch()` that sends error to client and updates conversation status
- [ ] `KeyInvalidError` instances in the catch handler attach `errorCode: "key_invalid"` (consistent with existing error handling in `startAgentSession`'s internal catch block)
- [ ] Existing tests pass (`bun test` in `apps/web-platform/`)

## Test Scenarios

- Given a user with no API key, when `start_session` is received, then the client receives `{ type: "error", errorCode: "key_invalid" }` (not an unhandled rejection)
- Given a user whose workspace is not provisioned, when `sendUserMessage` triggers a new agent turn, then the client receives `{ type: "error", message: "Workspace not provisioned" }`
- Given an active session running normally, when the agent completes, then behavior is unchanged (the `.catch()` never fires)

## Context

- Discovered during code review of PR #721
- Pre-existing since the MVP commit
- Related learning: `knowledge-base/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md`

## References

- Issue: #727
- File: `apps/web-platform/server/agent-runner.ts:296`
- File: `apps/web-platform/server/ws-handler.ts:130`
