# Learning: WebSocket First-Message Auth TOCTOU Race

## Problem

When migrating WebSocket authentication from URL query string (`?token=...`) to first-message auth (CWE-598 fix, issue #730), a TOCTOU race emerged between the auth timeout timer and the async token validation call.

The server enforces a 5-second auth timeout via `setTimeout`. The token validation (`supabase.auth.getUser(token)`) is async and can take variable time. If the timeout fires *during* the `await`, the timeout callback calls `ws.close(4001, "Auth timeout")`, transitioning the socket to CLOSING state. But when the `await` resumes on the success path, the code proceeds to register the now-dead socket in the `sessions` Map:

```
sessions.set(userId, { ws });  // ws is CLOSING — registered but unreachable
```

This creates a phantom session: the user appears connected in the sessions Map, but the socket is closing. Subsequent `sendToClient()` calls silently fail because the existing `readyState` guard in `sendToClient` catches it — but the session slot is occupied, so a reconnect attempt gets its *new* socket superseded by the phantom entry's close logic, creating a reconnect loop.

## Solution

Added a `ws.readyState !== WebSocket.OPEN` guard after the `await` and before session registration:

```typescript
// Validate token via Supabase
const {
  data: { user },
  error,
} = await supabase.auth.getUser(msg.token);

if (error || !user) {
  clearTimeout(authTimer);
  ws.close(4001, "Unauthorized");
  return;
}

// Guard: if timeout fired during the await, socket is already closing
if (ws.readyState !== WebSocket.OPEN) {
  clearTimeout(authTimer);
  return;
}

// Auth success — safe to register
clearTimeout(authTimer);
authenticated = true;
userId = user.id;
sessions.set(userId, { ws });
```

The guard is placed *after* the auth check (no point guarding before — a failed auth closes the socket anyway) and *before* any state mutation (`authenticated = true`, `sessions.set()`). The `clearTimeout(authTimer)` after the guard is defensive — if the timeout already fired, `clearTimeout` is a no-op, but it prevents a second fire in edge cases where the timer hasn't executed yet but the socket was closed by the client.

## Key Insight

Any time an async operation (network call, database query, file I/O) sits between a timer-based deadline and a state mutation, you have a TOCTOU window. The timer and the async continuation run on the same event loop, so they can't truly race in the concurrency sense — but the timer callback can execute in the microtask gap between the `await` yield and its resumption.

The general pattern for async-with-timeout in WebSocket handlers:

1. Start timeout timer
2. `await` the async operation
3. Check for error/rejection from the operation
4. **Check socket state** — the timeout may have fired during step 2
5. Only then mutate shared state (session maps, flags, intervals)

This is the WebSocket equivalent of the file-system TOCTOU pattern documented in `2026-03-18-stop-hook-toctou-race-fix.md`: check-then-act across an async boundary requires re-validation of the precondition after the boundary.

## Session Errors

1. **Missing `node_modules` in worktree**: `npx vitest run` failed because worktrees don't inherit `node_modules` from the main checkout. Fix: always run `npm install` after entering a worktree. This is the same error documented in `2026-03-18-typed-error-codes-websocket-key-invalidation.md` — the lesson hasn't been internalized into a pre-flight check.
2. **TOCTOU race missed in initial implementation**: The race was only discovered during code review, not during implementation. Async-with-timeout is a known race pattern — it should be part of an implementation checklist for any WebSocket auth handler, not left to review to catch.

## Tags
category: security-issues
module: web-platform/ws-handler
