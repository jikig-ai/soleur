---
title: "feat: abort active agent sessions during SIGTERM shutdown"
type: feat
date: 2026-04-06
deepened: 2026-04-06
---

# feat: abort active agent sessions during SIGTERM shutdown

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Test Scenarios, Design Note)
**Research sources:** Claude Agent SDK docs (Context7), institutional learnings (3), codebase analysis

### Key Improvements

1. Documented SDK `Query` interface methods (`close()`, `interrupt()`) from official docs -- confirms `close()` is the right method for forceful termination and validates the design decision to defer it
2. Incorporated learnings from review-gate-promise-leak (#840) -- `timer.unref()` pattern and reject-not-resolve for abort paths
3. Applied fire-and-forget promise safety pattern -- the existing catch block in `startAgentSession` already has proper `.catch()` on the Supabase status update
4. Added edge case: catch block distinguishes "server_shutdown" from "superseded" abort reasons to ensure correct status write ("failed" not skipped)

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

Create a new exported function that iterates all entries in the `activeSessions` Map and calls `controller.abort()` on each, with a "shutdown" reason.

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

### Design note: `AbortController.abort()` vs `Query.close()`

The SDK's `Query` object has a `close()` method that "forcefully ends the query, cleaning up all resources including pending requests, MCP transports, and the CLI subprocess." This is more thorough than `AbortController.abort()`, which only sets a signal flag checked by application code.

However, the `query()` return value is not currently stored in the `AgentSession` type or in `activeSessions`. Storing it would require modifying the `AgentSession` interface and `startAgentSession` to capture the `Query` reference. This is a larger refactor with broader implications for the session lifecycle.

**Decision: Use `AbortController.abort()` only.** This matches the existing abort patterns (disconnect, superseded, account_deleted) and is sufficient to stop the for-await loop. The process exit that follows shortly will kill any remaining CLI subprocesses. A future enhancement could store the `Query` reference and call `close()` for cleaner subprocess termination, but that is out of scope for this issue.

#### Research: SDK `Query` interface (from official docs)

The Claude Agent SDK TypeScript `Query` interface extends `AsyncGenerator<SDKMessage, void>` and provides these termination methods:

- **`close(): void`** -- "Close the query and terminate the underlying process. This forcefully ends the query, cleaning up all resources including pending requests, MCP transports, and the CLI subprocess." This is the right method for shutdown scenarios.
- **`interrupt(): Promise<void>`** -- Stops a running task within a session, allowing recovery and new queries. This is for mid-session interruption, not termination.
- **`stopTask(taskId): Promise<void>`** -- Stops a specific background task by ID.

For a future `Query.close()` integration, the `AgentSession` interface in `review-gate.ts` would need a `query: Query | null` field, set after the `query()` call returns in `startAgentSession`. The `abortAllSessions()` function would then call both `session.query?.close()` (kill subprocess) and `session.abort.abort()` (signal application code).

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

- [x] `abortAllSessions()` exported from `agent-runner.ts`
- [x] SIGTERM handler calls `abortAllSessions()` before WebSocket close loop
- [x] Agent SDK sessions receive abort signal during shutdown (AbortController.abort() called)
- [x] Conversation status updated to "failed" in database during shutdown (handled by existing catch block in `startAgentSession`)
- [x] Existing abort patterns (disconnect, superseded, account_deleted) are not affected
- [x] No new dependencies added

## Test Scenarios

- Given the server has active agent sessions, when SIGTERM is received, then `abortAllSessions()` is called before WebSocket clients are closed
- Given `abortAllSessions()` is called, when there are 3 active sessions, then all 3 sessions' AbortControllers have `.abort()` called with a "server_shutdown" reason
- Given `abortAllSessions()` is called, when there are 0 active sessions, then it completes without error (no-op)
- Given `abortAllSessions()` is called and a session's abort triggers the catch block, then the conversation status is updated to "failed" (not left as "active")
- Given `abortAllSessions()` is called with reason "server_shutdown", when the catch block checks `isSuperseded`, then it does NOT skip the "failed" status write (only "superseded" skips it)

### Research Insights: Edge Cases

**Abort reason routing in catch block (from learning: ws-session-race-abort-before-replace):**

The existing catch block at line 582-597 in `agent-runner.ts` has special handling for the "superseded" abort reason -- it skips the "failed" status write because the caller (`abortActiveSession` in ws-handler) already set status to "completed". The "server_shutdown" reason must NOT trigger the `isSuperseded` check, or conversations will be left in "active" status. The current code checks `err.message.includes("superseded")`, so "server_shutdown" will correctly fall through to the "failed" status write. No code change needed -- verify this in tests.

**Fire-and-forget Supabase call safety (from learning: fire-and-forget-promise-catch-handler):**

The `updateConversationStatus(conversationId, "failed")` call at line 589 already has a `.catch()` handler (lines 589-595). This is correct -- during shutdown, the Supabase client may fail (connection pool closed, network down), and an unhandled rejection from a fire-and-forget call would cause a different process exit path than intended. No code change needed.

**`timer.unref()` pattern (from learning: review-gate-promise-leak-abort-timeout):**

The existing review gate safety-net timers (5-minute timeout) use `.unref()` so they do not block graceful shutdown. This is already correct. `abortAllSessions()` will trigger the abort signal which cleans up these timers via the `onAbort` handler in `abortableReviewGate()`. No code change needed.

## Context

This is a follow-up to #1547 (graceful SIGTERM shutdown), which explicitly scoped this out as a non-goal: "Agent sessions are long-running and cannot be drained in 8 seconds. The existing `cleanupOrphanedConversations()` on startup handles recovery." This issue tracks the improvement of proactively aborting sessions to stop API credit consumption immediately rather than waiting for process exit.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## References

### Issues and PRs

- Related issue: #1547 (graceful SIGTERM shutdown -- closed)
- Related issue: #1554 (this issue)

### Source Files

- `apps/web-platform/server/agent-runner.ts` -- activeSessions map, abortSession patterns, startAgentSession catch block
- `apps/web-platform/server/index.ts:79-105` -- SIGTERM handler
- `apps/web-platform/server/ws-handler.ts:564-592` -- disconnect grace period
- `apps/web-platform/server/review-gate.ts` -- AgentSession interface, abortableReviewGate
- `apps/web-platform/test/review-gate.test.ts` -- existing test pattern for abort-related tests

### Institutional Learnings

- `knowledge-base/project/learnings/2026-04-05-graceful-sigterm-shutdown-node-patterns.md` -- SIGTERM shutdown sequence, `server.closeIdleConnections()`, `forceExit.unref()`
- `knowledge-base/project/learnings/2026-03-27-ws-session-race-abort-before-replace.md` -- abort reason routing ("superseded" vs other), `isSuperseded` check in catch block
- `knowledge-base/project/learnings/2026-03-20-review-gate-promise-leak-abort-timeout.md` -- `timer.unref()` for safety-net timers, abort signal cleanup, reject-not-resolve pattern
- `knowledge-base/project/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md` -- `.catch()` required on all fire-and-forget promises

### External Documentation

- [Claude Agent SDK TypeScript docs](https://platform.claude.com/docs/en/agent-sdk/typescript) -- `Query` interface with `close()`, `interrupt()`, `stopTask()` methods
- [Claude Agent SDK overview](https://platform.claude.com/docs/en/agent-sdk/overview) -- session resume and lifecycle patterns
