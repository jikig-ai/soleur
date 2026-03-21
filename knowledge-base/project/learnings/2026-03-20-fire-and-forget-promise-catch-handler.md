# Learning: Fire-and-forget async calls require explicit .catch() to prevent process termination

## Problem

`startAgentSession()` was called fire-and-forget (no `await`, no `.catch()`) in two locations:

- `apps/web-platform/server/ws-handler.ts:130` (WebSocket `start_session` handler)
- `apps/web-platform/server/agent-runner.ts:296` (`sendUserMessage` function)

The function has an internal try/catch that handles errors during the agent session loop, so it appeared safe. However, if the promise rejects *before* the internal try block engages (e.g., during API key lookup, client creation, or a future refactor adding code before the try), the rejection escapes unhandled. On Node 22 (`--unhandled-rejections=throw` by default since Node 15), this terminates the entire server process -- affecting all connected users, not just the one whose session failed.

## Solution

Add `.catch()` handlers at both call sites that log the error, notify the client via WebSocket, and (where applicable) mark the conversation as failed:

```typescript
// ws-handler.ts -- WebSocket session start
startAgentSession(userId, conversationId, msg.leaderId).catch(
  (err) => {
    console.error(`[ws] startAgentSession error:`, err);
    const message =
      err instanceof Error ? err.message : "Failed to start session";
    sendToClient(userId, {
      type: "error",
      message,
      errorCode:
        err instanceof KeyInvalidError ? "key_invalid" : undefined,
    });
  },
);
```

```typescript
// agent-runner.ts -- new agent turn from user message
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
  updateConversationStatus(conversationId, "failed").catch((statusErr) => {
    console.error(
      `[agent] Failed to mark conversation ${conversationId} as failed:`,
      statusErr,
    );
  });
});
```

Key details:

- The `.catch()` handlers are defense-in-depth: `startAgentSession` has an internal try/catch, so the `.catch()` only fires for rejections that escape before the try block
- Double error delivery cannot happen because the internal catch resolves (not rejects) the promise
- `KeyInvalidError` is checked with `instanceof` (not string matching) to attach `errorCode: "key_invalid"`, which the client uses for redirect logic
- `updateConversationStatus` in the agent-runner catch gets its own `.catch()` with a logged error -- never swallow errors silently with `.catch(() => {})`
- `KeyInvalidError` import in ws-handler.ts was changed from type-only to value import to support `instanceof` at runtime

## Key Insight

An internal try/catch inside an async function does not make fire-and-forget calls safe. The `.catch()` on the returned promise is a separate error boundary that catches rejections escaping *before* the function's try block. Every fire-and-forget promise needs an explicit `.catch()` -- not because the current code can throw there, but because the promise boundary is the contract, and future refactors can silently introduce pre-try-block throwing code. Enable `@typescript-eslint/no-floating-promises` to enforce this statically.

## Tags

category: reliability
module: web-platform
tags: promises, error-handling, node, fire-and-forget, defense-in-depth
date: 2026-03-20
