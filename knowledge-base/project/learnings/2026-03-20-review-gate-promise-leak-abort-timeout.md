---
title: "Review gate promise leak: hanging promise on user disconnect leaked AgentSession objects"
date: 2026-03-20
category: runtime-errors
module: web-platform/agent-runner
tags:
  - promise-leak
  - resource-leak
  - abort-signal
  - websocket-disconnect
  - review-gate
severity: high
related_issues:
  - 840
---

# Learning: Review gate promise leak -- hanging promise on user disconnect leaked AgentSession objects

## Problem

When the agent runner hit a review gate (waiting for user approval), it created a promise that resolved only when the user responded via WebSocket. If the user disconnected (closed browser, network drop, session timeout), the promise hung forever. This caused:

1. **AgentSession object leak** -- the session remained in memory indefinitely, held alive by the unresolved promise's closure over the session context.
2. **Conversation stuck in `waiting_for_user` status** -- with no mechanism to transition to `failed`, the conversation appeared permanently frozen in the UI.
3. **Unbounded accumulation** -- each disconnected session added another leaked object. Under sustained usage, this is a slow memory leak that compounds over time.

## Root Cause

The review gate promise had no timeout and no cancellation path. It was a bare `new Promise((resolve) => { map.set(id, resolve) })` with the resolver stored in a map. The only way to resolve it was a WebSocket message calling `resolveReviewGate(id, decision)`. No code path existed for:

- User disconnect (WebSocket close event)
- Server-side timeout (safety net)
- Graceful shutdown (process termination)

The WebSocket close handler did not know about running agent sessions, so disconnect events were silently ignored by the agent runner.

## Solution

1. **Created `review-gate.ts`** with `abortableReviewGate()` -- wraps the review gate promise with AbortSignal awareness and a 5-minute timeout safety net. Uses manual `setTimeout` + `clearTimeout` rather than `AbortSignal.timeout()` for precise timer cleanup (see Key Insight below). Calls `timer.unref()` so the safety-net timer does not keep the Node.js process alive during shutdown.

2. **Exported `abortSession()` from `agent-runner.ts`** -- accepts a session ID, calls `abort()` on the session's AbortController. This gives external code (WebSocket handler) a clean way to cancel a running agent session.

3. **Wired `ws-handler.ts` close event to `abortSession()`** -- when a WebSocket disconnects, the close handler now aborts any running agent session for that connection (inside the existing identity guard scope where the session ID is known).

4. **Added conversation status update** -- the abort catch path updates the conversation status to `failed` so the UI reflects the actual state instead of showing `waiting_for_user` forever.

5. **Added safe error messages in `error-sanitizer.ts`** -- "Session timed out" and "Session disconnected" messages are allowlisted so they pass through to the client without being replaced by a generic error.

6. **Extracted into `review-gate.ts` for testability** -- following the `tool-path-checker.ts` pattern of extracting testable logic into a standalone module, avoiding `@/` path alias issues that prevent direct import in vitest.

## Key Insight

### AbortSignal.timeout() and AbortSignal.any() leak timers

`AbortSignal.timeout(ms)` creates an internal timer that fires after `ms` milliseconds. If the operation completes normally before the timeout, the timer is **not cleared** -- it continues to exist until it fires (at which point it aborts a signal nobody is listening to). `AbortSignal.any([signal1, signal2])` has the same issue: it subscribes to all constituent signals and does not unsubscribe when one fires.

For short-lived operations this is harmless. For a 5-minute safety-net timeout on a promise that usually resolves in seconds, it means thousands of unnecessary pending timers under load. The fix is manual `setTimeout` + `clearTimeout` with cleanup in both the resolve and reject paths:

```typescript
const timer = setTimeout(() => reject(new Error("timeout")), ms);
timer.unref(); // don't keep process alive
// ... on resolve or reject:
clearTimeout(timer);
```

### Reject, don't resolve with a synthetic value

When aborting a review gate, the promise is **rejected** (not resolved with a fake "deny" decision). Rejection flows through the existing `catch`/`finally` cleanup paths in the agent runner, which already handle errors by updating conversation status and releasing resources. Resolving with a synthetic value would have required the happy path to distinguish real user decisions from abort-injected ones -- a fragile coupling.

### timer.unref() for safety-net timers

`timer.unref()` tells Node.js not to keep the event loop alive solely for this timer. Without it, a 5-minute safety-net timer would prevent graceful shutdown for up to 5 minutes after the last real work completes. This matters for serverless/container environments where fast shutdown is expected.

## Session Errors

1. **`npx vitest` failed with native binding error** -- the worktree had no `node_modules`. Fix: run `npm install` in the app directory before running tests. Worktrees do not share `node_modules` with the main checkout.

2. **Test expected `"Session aborted"` but got DOMException** -- when `AbortController.abort()` is called without a reason argument, Node.js sets `signal.reason` to a `DOMException` with name `"AbortError"`, not a plain string. Fix: either pass an explicit reason to `abort(new Error("Session aborted"))` or check `signal.reason.message` in assertions.

3. **`@/` path alias blocked direct import in tests** -- `agent-runner.ts` uses `@/` path aliases (tsconfig paths) that vitest resolves via its config, but importing a file that uses `@/` from a test that imports the extracted module transitively pulls in the alias. Fix: extract the testable function into a standalone file (`review-gate.ts`) with no `@/` imports, following the `tool-path-checker.ts` pattern.

4. **False assertion about resolver self-deletion** -- initial test assumed the resolver callback stored in the map would delete itself when called. In fact, `resolveReviewGate()` (the caller) handles map deletion after invoking the resolver. Fix: read the actual code before writing assertions about cleanup behavior.

## Prevention

1. **Every long-lived promise needs a cancellation path.** If a promise waits on external input (user action, remote service, webhook), it must accept an AbortSignal or have a timeout. Promises without cancellation paths are resource leaks waiting for a disconnect.

2. **WebSocket disconnect must propagate to all owned resources.** When a connection drops, every resource scoped to that connection (running agents, pending promises, open streams) must be cleaned up. Audit WebSocket close handlers to ensure they reach all resource owners.

3. **Use `timer.unref()` on safety-net timers.** Any timer that exists solely as a fallback (not part of the critical path) should be unref'd to avoid blocking graceful shutdown.

4. **Extract for testability early.** When a function is deeply embedded in a module with path aliases and heavy imports, extract it into a standalone file before writing tests. Fighting the import system wastes more time than the extraction takes.

5. **Test abort behavior with explicit reasons.** When testing AbortController/AbortSignal, always pass an explicit reason string to `abort()` so assertions are deterministic. Relying on the default DOMException behavior couples tests to a Node.js implementation detail.

## Tags

category: runtime-errors
module: web-platform/agent-runner
