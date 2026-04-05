---
title: "fix: add graceful HTTP/WebSocket drain to SIGTERM handler"
type: fix
date: 2026-04-05
---

# fix: add graceful HTTP/WebSocket drain to SIGTERM handler

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 4 (Proposed Solution, Implementation Details, Test Scenarios, Edge Cases)
**Research sources:** Context7 (ws v8.18, Node.js v22 HTTP API), RFC 6455, project learnings

### Key Improvements

1. Added `server.closeIdleConnections()` call after `server.close()` to immediately close HTTP keep-alive connections that would otherwise block shutdown
2. Identified that `wss.close()` is redundant when `noServer: true` is used -- the plan correctly uses `server.close()` + explicit client iteration instead
3. Added re-entrancy guard to prevent double-shutdown from multiple SIGTERM deliveries
4. Added edge case handling for the review-gate promise leak interaction (learning from `2026-03-20-review-gate-promise-leak-abort-timeout.md`)

### New Considerations Discovered

- Node.js `server.close()` does NOT close keep-alive connections -- `server.closeIdleConnections()` (available since Node 18.2.0) is needed
- The `ws` library's `wss.close()` does NOT close the underlying HTTP server when `noServer: true` is used, which is this project's pattern -- so `server.close()` must be called separately (plan already does this correctly)
- Multiple SIGTERM signals can be delivered if the first handler takes time -- a re-entrancy guard prevents double-shutdown

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

1. **Stop accepting new connections** -- call `server.close()` on the HTTP server, then `server.closeIdleConnections()` to immediately release keep-alive connections not currently serving a request
2. **Close WebSocket connections gracefully** -- iterate all connected clients via the `WebSocketServer` instance and close each with code `1001` ("Going Away") and a human-readable reason
3. **Flush Sentry events** -- `Sentry.flush(2000)` (existing behavior)
4. **Exit after drain or hard timeout** -- `process.exit(0)` after all connections close, or after an 8-second hard deadline (leaves 2s buffer before Docker's 10s SIGKILL)

### Research Insights

**Best Practices (from Context7 ws v8.18 docs + Node.js v22 API):**

- The `ws` library's `server.close()` (on WebSocketServer) does NOT close the underlying HTTP server when `noServer: true` is used -- the HTTP server must be closed separately. This project uses `noServer: true`, so `server.close()` on the HTTP server is the correct call.
- `wss.clients.forEach(client => client.close(1001, "..."))` is the canonical pattern from the ws library docs for graceful shutdown.
- Node.js `server.close()` stops new connections but keeps existing ones alive (including idle keep-alive connections). Call `server.closeIdleConnections()` immediately after to release idle keep-alive connections. Available since Node 18.2.0; this project uses Node 22.
- `server.closeAllConnections()` forcefully terminates ALL connections (including active ones). Reserve this for the hard-deadline timeout path.

**Performance Considerations:**

- WebSocket close handshake involves sending a close frame and waiting for the peer's close frame response. With many clients this is fast (sub-millisecond per client) since `client.close()` is non-blocking -- it queues the close frame and returns immediately.
- `Sentry.flush(2_000)` is the bottleneck -- it waits up to 2 seconds for events to drain. This is acceptable within the 8-second budget.

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
import { WebSocket } from "ws";

const SHUTDOWN_TIMEOUT_MS = 8_000; // 2s buffer before Docker's 10s SIGKILL

let shuttingDown = false;

process.on("SIGTERM", async () => {
  // Re-entrancy guard: Docker may deliver multiple SIGTERMs
  if (shuttingDown) return;
  shuttingDown = true;

  log.info("SIGTERM received, starting graceful shutdown...");

  // Hard deadline: force exit if drain exceeds 8s
  const forceExit = setTimeout(() => {
    log.warn("Shutdown timeout reached, forcing exit");
    server.closeAllConnections();
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  forceExit.unref();

  // 1. Stop accepting new HTTP connections and close idle keep-alives
  server.close();
  server.closeIdleConnections();

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

### Edge Cases

**Multiple SIGTERM delivery:** Docker sends SIGTERM and waits. If the process hasn't exited after 10 seconds, it sends SIGKILL. However, process managers or orchestrators may deliver SIGTERM more than once. The `shuttingDown` boolean prevents double-execution.

**Keep-alive connections blocking shutdown:** HTTP/1.1 connections with `Connection: keep-alive` (the default) stay open even after `server.close()`. The `server.closeIdleConnections()` call handles idle ones immediately. Active connections (mid-request) will complete naturally or be terminated by the `server.closeAllConnections()` call in the hard-deadline timeout.

**Review gate promise leak interaction:** Per learning `2026-03-20-review-gate-promise-leak-abort-timeout.md`, agent sessions waiting on review gates hold promises that only resolve on user WebSocket messages. When the server closes all WebSocket connections during shutdown, these promises will never resolve -- but that's acceptable because `process.exit()` terminates all pending promises. The orphan cleanup on next startup handles the state recovery.

**No active connections:** When SIGTERM fires with zero active connections, the handler completes in milliseconds (just the Sentry flush). No special case needed.

## Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/server/index.ts` | Replace SIGTERM handler, capture `wss` from `setupWebSocket`, import `WebSocket`, add re-entrancy guard, add `closeIdleConnections()` |
| `apps/web-platform/lib/types.ts` | Add `SERVER_GOING_AWAY: 1001` to `WS_CLOSE_CODES` |
| `apps/web-platform/test/server/shutdown.test.ts` | New test file for graceful shutdown behavior |

## Acceptance Criteria

- [ ] SIGTERM handler calls `server.close()` and `server.closeIdleConnections()` before `process.exit()`
- [ ] WebSocket connections are closed with code `1001` and "Server shutting down" message
- [ ] Sentry events are flushed within the shutdown window
- [ ] Total shutdown completes within Docker's 10-second grace period (8s hard timeout in code)
- [ ] Client auto-reconnects after server restart (code 1001 is not in `NON_TRANSIENT_CLOSE_CODES`)
- [ ] Re-entrancy guard prevents double-shutdown from multiple SIGTERM deliveries
- [ ] Hard-deadline timeout calls `server.closeAllConnections()` before force-exit
- [ ] No new dependencies added

## Test Scenarios

- Given a running server with no active connections, when SIGTERM is received, then the server calls `server.close()` and exits within 8 seconds
- Given a running server with open WebSocket connections, when SIGTERM is received, then all WebSocket clients receive close frame with code 1001 before the server exits
- Given a running server, when SIGTERM is received, then `Sentry.flush()` is called before `process.exit()`
- Given a running server with a slow-draining connection, when SIGTERM is received and 8 seconds elapse, then the server force-exits with code 1
- Given the client receives close code 1001 from the server, when checking `NON_TRANSIENT_CLOSE_CODES`, then code 1001 is not present (client will auto-reconnect)
- Given SIGTERM is delivered twice in quick succession, when the handler runs, then the second invocation is a no-op (re-entrancy guard)
- Given the `WS_CLOSE_CODES` object, when inspecting values, then `SERVER_GOING_AWAY` equals 1001 and all values are unique

### Test Implementation Notes

Tests for this feature are primarily unit-level checks on close codes and contract verification. The SIGTERM handler itself is integration-level (requires a real HTTP server and process signals) -- defer full integration testing to QA phase with a running dev server. The unit tests validate:

1. **Close code contract** -- `SERVER_GOING_AWAY` is 1001, all codes are unique, 1001 is not in `NON_TRANSIENT_CLOSE_CODES`
2. **Type safety** -- `WS_CLOSE_CODES.SERVER_GOING_AWAY` exists and is typed correctly

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/reliability improvement to existing server shutdown logic.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Use custom close code (4010+) for shutdown | Explicit server-shutdown signal | Requires client-side changes to handle new code; standard 1001 already means "Going Away" | Rejected -- 1001 is the RFC standard |
| Wait for all HTTP responses via `server.close()` callback | Most graceful; callback fires when all connections are closed | Keep-alive connections can delay callback for 5+ minutes; need `closeIdleConnections()` anyway | Adopted partially -- use callback as an optimization but don't depend on it for the exit path |
| Use `http-terminator` npm package | Well-tested library | New dependency for ~20 lines of code; constitution says "never add a dependency for something an LLM can generate inline" | Rejected |
| Call `wss.close()` instead of iterating clients | Cleaner API | With `noServer: true`, `wss.close()` does NOT close existing connections or the HTTP server -- it only stops accepting new WebSocket upgrades. Still need to iterate `wss.clients` for graceful close frames. | Rejected -- use explicit client iteration |
| Use `server.closeAllConnections()` immediately | Fastest shutdown | Kills in-flight HTTP requests without letting them complete; defeats the purpose of graceful drain | Rejected for initial call -- used only in hard-deadline timeout |

## Non-Goals

- **Connection draining with timeout per connection** -- `server.close()` stops accepting new connections; existing HTTP responses will naturally complete or be killed by the 8s hard timeout. Per-connection tracking is unnecessary complexity.
- **Graceful agent session handoff** -- Agent sessions are long-running and cannot be drained in 8 seconds. The existing `cleanupOrphanedConversations()` on startup handles recovery.
- **Client-side close code handling changes** -- Code 1001 is already treated as transient by the client (not in `NON_TRANSIENT_CLOSE_CODES`), triggering auto-reconnect. No client changes needed.

## References

- Related issue: [#1547](https://github.com/jikig-ai/soleur/issues/1547)
- Source: PR #1539 review finding
- [RFC 6455 Section 7.4.1](https://datatracker.ietf.org/doc/html/rfc6455#section-7.4.1): WebSocket Close Code 1001 "Going Away"
- [Node.js v22 server.close()](https://nodejs.org/docs/latest-v22.x/api/net.html#serverclosecallback): stops accepting new connections, keeps existing
- [Node.js v22 server.closeIdleConnections()](https://nodejs.org/docs/latest-v22.x/api/net.html#servercloseidleconnections): closes idle keep-alive connections
- [Node.js v22 server.closeAllConnections()](https://nodejs.org/docs/latest-v22.x/api/net.html#servercloseallconnections): forcefully terminates all connections
- [ws library graceful shutdown pattern](https://github.com/websockets/ws#graceful-close): `wss.clients.forEach(client => client.close(1001, "..."))`
- Learning: `2026-03-20-review-gate-promise-leak-abort-timeout.md` -- review gate promises hang on disconnect; shutdown must not depend on their resolution
- Learning: `sentry-dsn-missing-from-container-env-20260405.md` -- documents the current SIGTERM handler and Sentry flush pattern
