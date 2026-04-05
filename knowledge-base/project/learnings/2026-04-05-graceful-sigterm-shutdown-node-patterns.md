---
title: "Node.js graceful SIGTERM shutdown requires explicit idle connection and WebSocket drain"
category: runtime-errors
module: web-platform/server
tags: [sigterm, graceful-shutdown, websocket, docker, node-http]
date: 2026-04-05
---

# Learning: Node.js graceful SIGTERM shutdown requires explicit idle connection and WebSocket drain

## Problem

The web-platform SIGTERM handler called `Sentry.flush(2000)` then `process.exit(0)` without draining HTTP connections or closing WebSocket clients. During container restarts (`docker stop`), in-flight HTTP requests were dropped and WebSocket clients experienced unclean disconnects with no indication the server was going away.

## Solution

Replaced the handler with a proper graceful shutdown sequence:

1. **Re-entrancy guard** (`let shuttingDown = false`) — Docker or orchestrators may deliver multiple SIGTERMs
2. **Hard-deadline timer** (8s, `.unref()`'d) — calls `server.closeAllConnections()` + `process.exit(1)` as last resort before Docker's 10s SIGKILL
3. **`server.close()`** — stops accepting new connections
4. **`server.closeIdleConnections()`** — immediately releases idle HTTP keep-alive connections that `server.close()` does NOT close
5. **WebSocket client iteration** — close each with code 1001 (RFC 6455 "Going Away") so clients auto-reconnect
6. **`Sentry.flush(2_000)`** — preserve existing telemetry behavior
7. **`process.exit(0)`** — clean exit

## Key Insights

### `server.close()` does NOT close idle keep-alive connections

This is the most important non-obvious behavior. Node.js `server.close()` stops accepting new connections but keeps existing ones alive — including idle HTTP/1.1 keep-alive connections that have no pending request. Call `server.closeIdleConnections()` (available since Node 18.2) immediately after `server.close()` to release these. Reserve `server.closeAllConnections()` for the hard-deadline timeout only — it kills in-flight requests.

### `wss.close()` is redundant with `noServer: true`

When the `ws` WebSocketServer is configured with `noServer: true` (this project's pattern), calling `wss.close()` does NOT close the underlying HTTP server or existing connections. It only stops accepting new WebSocket upgrade requests. Since `server.close()` already blocks new TCP connections (and therefore new upgrades), `wss.close()` is unnecessary. Use explicit `wss.clients` iteration instead to send close frames with the correct code.

### Close code 1001 triggers client auto-reconnect without client-side changes

RFC 6455 code 1001 ("Going Away") is the standard for server shutdown. The client's `NON_TRANSIENT_CLOSE_CODES` map does not include 1001, so the client treats it as a transient failure and auto-reconnects with exponential backoff. No client-side changes needed.

### `forceExit.unref()` is critical

Without `.unref()`, the hard-deadline timer keeps the Node.js event loop alive even after all connections have drained and `process.exit(0)` would otherwise be reached naturally. The timer must not prevent exit on the happy path.

## Session Errors

1. **Worktree manager script reported success but directory was missing** — The `worktree-manager.sh --yes create feat-graceful-sigterm-drain` script output "Worktree created successfully!" but the directory did not exist afterward. Recovery: recreated manually with `git worktree add`. **Prevention:** Verify worktree directory exists after creation script runs; add a post-creation check to worktree-manager.sh.

2. **Lefthook bun-test false positive failure** — Lefthook reported `bun-test` as failed (exit code 1) despite all 1207 tests passing with 0 failures. The intentional error test cases in telegram-bridge print error messages to stderr (`error: stdin broken`, `error: async fail`) which lefthook may interpret as failure. Recovery: verified tests pass manually, committed with `LEFTHOOK=0`. **Prevention:** Known lefthook/worktree interaction issue. The `LEFTHOOK=0` workaround is documented in AGENTS.md.

3. **Draft PR creation failed — no commits between branches** — `gh pr create --draft` failed with "No commits between main and feat-graceful-sigterm-drain" because the branch was freshly created. Recovery: deferred PR creation to after the first real commit. **Prevention:** In the one-shot pipeline, create the draft PR after the first implementation commit, not at branch creation time.

## Tags

category: runtime-errors
module: web-platform/server
