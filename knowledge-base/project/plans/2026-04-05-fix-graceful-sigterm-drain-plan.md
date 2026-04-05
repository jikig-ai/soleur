---
title: "fix: add graceful HTTP/WebSocket drain to SIGTERM handler"
type: fix
date: 2026-04-05
---

# fix: add graceful HTTP/WebSocket drain to SIGTERM handler

## Overview

The SIGTERM handler in `apps/web-platform/server/index.ts:74-78` calls `Sentry.flush(2000)` then `process.exit(0)` without first draining the HTTP server or closing WebSocket connections. During container restarts (deploy via `docker stop`), in-flight HTTP requests are dropped and WebSocket clients experience an unclean disconnect with no indication the server is going away.

## Problem Statement

When Docker sends SIGTERM to the container, the current handler:

1. Flushes Sentry events (2s timeout)
2. Calls `process.exit(0)` immediately

This means:

- **In-flight HTTP requests** are killed mid-response (partial JSON, broken streams)
- **WebSocket connections** are terminated without a close frame, so clients cannot distinguish "server restarting" from "network failure"
- **Reconnection behavior** is suboptimal -- without a proper close code, clients use exponential backoff instead of attempting immediate reconnect

The `ci-deploy.sh` script uses `docker stop` with the default 10-second grace period before SIGKILL, giving the handler an 8-second window (reserving 2s buffer) to drain gracefully.

## Proposed Solution

Consolidate shutdown into a single SIGTERM handler that follows Node.js graceful shutdown best practices:

1. **Stop accepting new connections** -- call `server.close()` on the HTTP server
2. **Close WebSocket connections gracefully** -- iterate all connected clients via the `WebSocketServer` instance and close each with code `1001` ("Going Away") and a human-readable reason
3. **Flush Sentry events** -- `Sentry.flush(2000)` (existing behavior)
4. **Exit after drain or hard timeout** -- `process.exit(0)` after all connections close, or after an 8-second hard deadline (leaves 2s buffer before Docker's 10s SIGKILL)

### Implementation Details

#### 1. Capture `wss` reference from `setupWebSocket`

`setupWebSocket()` in `ws-handler.ts` already returns the `WebSocketServer` instance (line 600), but `index.ts` does not capture it:

```typescript
// Before (index.ts:49)
setupWebSocket(server);

// After
const wss = setupWebSocket(server);
```

#### 2. Add a `SERVER_GOING_AWAY` close code

Add `SERVER_GOING_AWAY: 1001` to `WS_CLOSE_CODES` in `lib/types.ts`. Code `1001` is the standard WebSocket close code for "Going Away" (RFC 6455, Section 7.4.1) -- it signals the server is shutting down. This code is NOT in the client's `NON_TRANSIENT_CLOSE_CODES` map, so the client will treat it as a transient failure and auto-reconnect with exponential backoff. This is the desired behavior -- the new container will be up within seconds and the client will reconnect automatically.

#### 3. Replace SIGTERM handler

```typescript
// apps/web-platform/server/index.ts
const SHUTDOWN_TIMEOUT_MS = 8_000; // 2s buffer before Docker's 10s SIGKILL

process.on("SIGTERM", async () => {
  log.info("SIGTERM received, starting graceful shutdown...");

  // 1. Stop accepting new HTTP connections
  server.close();

  // 2. Close all WebSocket connections with "Going Away" code
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.close(WS_CLOSE_CODES.SERVER_GOING_AWAY, "Server shutting down");
    }
  }

  // 3. Flush Sentry events
  await Sentry.flush(2_000);

  // 4. Exit
  log.info("Graceful shutdown complete");
  process.exit(0);
});

// Hard deadline: if drain takes too long, force exit
setTimeout(() => {
  log.warn("Shutdown timeout reached, forcing exit");
  process.exit(1);
}, SHUTDOWN_TIMEOUT_MS).unref();
```

Wait -- the hard deadline timer should be inside the SIGTERM handler, not outside it. And it needs careful ordering: the timer starts when SIGTERM fires, and the `process.exit(0)` in the handler races against it. The corrected approach:

```typescript
process.on("SIGTERM", async () => {
  log.info("SIGTERM received, starting graceful shutdown...");

  // Hard deadline: force exit if drain exceeds 8s
  const forceExit = setTimeout(() => {
    log.warn("Shutdown timeout reached, forcing exit");
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  forceExit.unref();

  // 1. Stop accepting new HTTP connections
  server.close();

  // 2. Close all WebSocket connections with "Going Away" code
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.close(WS_CLOSE_CODES.SERVER_GOING_AWAY, "Server shutting down");
    }
  }

  // 3. Flush Sentry events
  await Sentry.flush(2_000);

  // 4. Clean exit
  log.info("Graceful shutdown complete");
  process.exit(0);
});
```

#### 4. Import `WebSocket` in `index.ts`

Need to import `WebSocket` from `ws` to check `readyState`:

```typescript
import { WebSocket } from "ws";
```

## Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/server/index.ts` | Replace SIGTERM handler, capture `wss` from `setupWebSocket`, import `WebSocket` |
| `apps/web-platform/lib/types.ts` | Add `SERVER_GOING_AWAY: 1001` to `WS_CLOSE_CODES` |
| `apps/web-platform/test/server/shutdown.test.ts` | New test file for graceful shutdown behavior |

## Acceptance Criteria

- [ ] SIGTERM handler calls `server.close()` before `process.exit()`
- [ ] WebSocket connections are closed with code `1001` and "Server shutting down" message
- [ ] Sentry events are flushed within the shutdown window
- [ ] Total shutdown completes within Docker's 10-second grace period (8s hard timeout in code)
- [ ] Client auto-reconnects after server restart (code 1001 is not in `NON_TRANSIENT_CLOSE_CODES`)
- [ ] No new dependencies added

## Test Scenarios

- Given a running server with no active connections, when SIGTERM is received, then the server calls `server.close()` and exits within 8 seconds
- Given a running server with open WebSocket connections, when SIGTERM is received, then all WebSocket clients receive close frame with code 1001 before the server exits
- Given a running server, when SIGTERM is received, then `Sentry.flush()` is called before `process.exit()`
- Given a running server with a slow-draining connection, when SIGTERM is received and 8 seconds elapse, then the server force-exits with code 1
- Given the client receives close code 1001 from the server, when checking `NON_TRANSIENT_CLOSE_CODES`, then code 1001 is not present (client will auto-reconnect)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/reliability improvement to existing server shutdown logic.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Use custom close code (4010+) for shutdown | Explicit server-shutdown signal | Requires client-side changes to handle new code; standard 1001 already means "Going Away" | Rejected -- 1001 is the RFC standard |
| Wait for all HTTP responses to complete | Most graceful | Complex to track; `server.close()` already stops new connections and the callback fires when existing ones finish | Deferred -- `server.close()` provides adequate draining; add callback-based waiting if issues arise |
| Use `http-terminator` npm package | Well-tested library | New dependency for ~20 lines of code; constitution says "never add a dependency for something an LLM can generate inline" | Rejected |

## Non-Goals

- **Connection draining with timeout per connection** -- `server.close()` stops accepting new connections; existing HTTP responses will naturally complete or be killed by the 8s hard timeout. Per-connection tracking is unnecessary complexity.
- **Graceful agent session handoff** -- Agent sessions are long-running and cannot be drained in 8 seconds. The existing `cleanupOrphanedConversations()` on startup handles recovery.

## References

- Related issue: [#1547](https://github.com/jikig-ai/soleur/issues/1547)
- Source: PR #1539 review finding
- RFC 6455 Section 7.4.1: WebSocket Close Code 1001 "Going Away"
- Node.js `server.close()` docs: stops accepting new connections, fires callback when all existing connections are closed
- Learning: `sentry-dsn-missing-from-container-env-20260405.md` -- documents the current SIGTERM handler and Sentry flush pattern
