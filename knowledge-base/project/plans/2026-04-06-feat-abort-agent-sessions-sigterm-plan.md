---
title: "feat: abort active agent sessions during SIGTERM shutdown"
type: feat
date: 2026-04-06
---

# feat: abort active agent sessions during SIGTERM shutdown

## Overview

The SIGTERM handler in `server/index.ts` closes WebSocket connections but does not abort active agent sessions tracked in `activeSessions` (agent-runner.ts). Running Claude Agent SDK `query()` sessions continue consuming API credits for responses nobody will see, and conversation status is left as "active" until `cleanupOrphanedConversations()` runs on next startup.

## Problem Statement

When the server receives SIGTERM (container restart, deployment), the shutdown sequence:

1. Stops accepting new connections (`server.close()`)
2. Closes idle connections (`server.closeIdleConnections()`)
3. Closes WebSocket clients with code 1001 ("Going Away")
4. Flushes Sentry
5. Exits with code 0

Missing from this sequence: aborting in-flight agent sessions. The `ws.on("close")` handler in ws-handler.ts starts a 30-second disconnect grace timer, but `process.exit(0)` fires within ~3 seconds (the 8-second hard deadline timer). This means:

- **Wasted API credits:** SDK `query()` sessions keep running until their subprocess is killed by process exit. The CLI subprocess may have already sent a request to the Anthropic API that will be answered and billed but never consumed.
- **Stale conversation status:** Conversations remain in "active" or "waiting_for_user" status until `cleanupOrphanedConversations()` runs on the next startup (5-minute stale threshold).
- **No clean abort signal:** The SDK `query()` object has a `close()` method that "forcefully ends the query, cleaning up all resources including pending requests, MCP transports, and the CLI subprocess." Without calling this, cleanup relies on process exit killing child processes.

## Proposed Solution

### 1. Export `abortAllSessions()` from `agent-runner.ts`

Create a new exported function that iterates all entries in the `activeSessions` Map and calls `controller.abort()` on each, with a "shutdown" reason. Also update each conversation's status to "failed" in the database (fire-and-forget, matching the existing pattern in the catch block).

```typescript
// apps/web-platform/server/agent-runner.ts

/** Abort ALL active sessions (called during server shutdown). */
export function abortAllSessions(): void {
  for (const [key, session] of activeSessions) {
    session.abort.abort(new Error("Session aborted: server_shutdown"));
  }
}
```

The `controller.abort()` call will:

- Cause the `for await` loop in `startAgentSession` to break (line 510: `if (controller.signal.aborted) break`)
- Trigger the catch block (line 582) which detects `controller.signal.aborted` and updates conversation status to "failed"
- The `finally` block (line 617) will clean up the `activeSessions` entry

### 2. Optionally export `shuttingDown` flag

Export a `shuttingDown` flag from server/index.ts so ws-handler's `ws.on("close")` can skip the 30-second grace period during shutdown. This is a minor optimization -- the grace timer has `.unref()` so it would not block process exit, but skipping it avoids unnecessary timer creation during shutdown.

**Decision: Skip this.** The grace timers are `.unref()`'d and the process exits before they fire. Adding a cross-module flag introduces coupling for negligible benefit. The existing `cleanupOrphanedConversations()` on startup handles any edge cases.

### 3. Call `abortAllSessions()` in SIGTERM handler

Add the call at the start of the shutdown sequence, before closing WebSocket connections:

```typescript
// apps/web-platform/server/index.ts (SIGTERM handler)
process.on("SIGTERM", async () => {
  if (shuttingDown) return;
  shuttingDown = true;

  log.info("SIGTERM received, starting graceful shutdown...");

  const forceExit = setTimeout(() => {
    log.warn("Shutdown timeout reached, forcing exit");
    server.closeAllConnections();
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  forceExit.unref();

  // Abort all active agent sessions first — stops API credit consumption
  // and updates conversation status to "failed" in the database.
  abortAllSessions();

  server.close();
  server.closeIdleConnections();

  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.close(WS_CLOSE_CODES.SERVER_GOING_AWAY, "Server shutting down");
    }
  }

  await Sentry.flush(2_000);

  log.info("Graceful shutdown complete");
  process.exit(0);
});
```

### Why `abortAllSessions()` before WebSocket close

Ordering matters:

1. **`abortAllSessions()` first:** Triggers `controller.abort()` on each session's AbortController. The `startAgentSession` function's catch block handles the abort: it updates conversation status to "failed" (fire-and-forget Supabase call) and the finally block removes the session from `activeSessions`.
2. **WebSocket close second:** Sends the 1001 close frame to clients. If we closed WebSockets first, the `ws.on("close")` handler would start 30-second grace timers for each session -- wasteful during shutdown.

## Files Changed

| File | Change |
|------|--------|
| `apps/web-platform/server/agent-runner.ts` | Add `abortAllSessions()` export |
| `apps/web-platform/server/index.ts` | Import and call `abortAllSessions()` in SIGTERM handler |
| `apps/web-platform/test/abort-all-sessions.test.ts` | Unit tests for `abortAllSessions()` |

## Acceptance Criteria

- [ ] `abortAllSessions()` exported from `agent-runner.ts`
- [ ] SIGTERM handler calls `abortAllSessions()` before WebSocket close loop
- [ ] Agent SDK sessions receive abort signal during shutdown (AbortController.abort() called)
- [ ] Conversation status updated to "failed" in database during shutdown (handled by existing catch block in `startAgentSession`)
- [ ] Existing abort patterns (disconnect, superseded, account_deleted) are not affected
- [ ] No new dependencies added

## Test Scenarios

- Given the server has active agent sessions, when SIGTERM is received, then `abortAllSessions()` is called before WebSocket clients are closed
- Given `abortAllSessions()` is called, when there are 3 active sessions, then all 3 sessions' AbortControllers have `.abort()` called with a "server_shutdown" reason
- Given `abortAllSessions()` is called, when there are 0 active sessions, then it completes without error (no-op)
- Given `abortAllSessions()` is called and a session's abort triggers the catch block, then the conversation status is updated to "failed" (not left as "active")

## Context

This is a follow-up to #1547 (graceful SIGTERM shutdown), which explicitly scoped this out as a non-goal: "Agent sessions are long-running and cannot be drained in 8 seconds. The existing `cleanupOrphanedConversations()` on startup handles recovery." This issue tracks the improvement of proactively aborting sessions to stop API credit consumption immediately rather than waiting for process exit.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## References

- Related issue: #1547 (graceful SIGTERM shutdown -- closed)
- Related issue: #1554 (this issue)
- File: `apps/web-platform/server/agent-runner.ts` (activeSessions map, abortSession patterns)
- File: `apps/web-platform/server/index.ts:79-105` (SIGTERM handler)
- File: `apps/web-platform/server/ws-handler.ts:564-592` (disconnect grace period)
- Learning: `knowledge-base/project/learnings/2026-04-05-graceful-sigterm-shutdown-node-patterns.md`
- SDK: `@anthropic-ai/claude-agent-sdk` Query.close() method for forceful termination
