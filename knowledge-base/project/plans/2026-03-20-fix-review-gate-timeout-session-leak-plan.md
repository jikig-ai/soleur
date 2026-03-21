---
title: "fix: review gate promise has no timeout, leaks agent sessions on disconnect"
type: fix
date: 2026-03-20
semver: patch
deepened: 2026-03-20
---

# fix: review gate promise has no timeout, leaks agent sessions on disconnect

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, MVP, Test Scenarios, Acceptance Criteria)
**Research sources:** Node.js v22 AbortSignal/AbortController documentation (Context7), project constitution, existing test patterns

### Key Improvements

1. Discovered `AbortSignal.any()` (Node 20+) and `AbortSignal.timeout()` as alternatives that could simplify the implementation -- but rejected in favor of the manual approach due to cleanup requirements on the resolver map
2. Identified that `error.name === 'AbortError'` is the canonical Node.js pattern for distinguishing abort rejections from other errors
3. Identified a potential issue with `abortSession` needing to handle multiple conversations per user (current `activeSessions` key is `userId:conversationId`, but the disconnect handler only has `userId` and one `conversationId`)
4. Added concrete concern about `unref()` on the timeout timer to prevent it from keeping the Node.js process alive during shutdown

### New Considerations Discovered

- The timeout `setTimeout` must call `timer.unref()` so it does not prevent clean server shutdown
- `AbortSignal.any()` creates a composite signal from multiple sources but does NOT auto-clear internal timers from `AbortSignal.timeout()`, making manual timer management preferable for this case
- The `ws-handler.ts` disconnect handler captures `conversationId` from `current.conversationId` which could be stale if the user started multiple sessions (superseded sessions)

## Overview

In `apps/web-platform/server/agent-runner.ts`, the review gate promise (lines 269-271) hangs indefinitely if the user disconnects or never responds. The WebSocket disconnect handler in `ws-handler.ts` removes the user from the `sessions` map but does not resolve or reject pending review gate promises in the `AgentSession` stored in `activeSessions`. This leaks the agent session, the AbortController, and the Claude Agent SDK query iterator -- all held alive by the unresolvable promise.

## Problem Statement

The bug has two concrete failure modes:

1. **Memory leak:** Each abandoned review gate keeps an `AgentSession` (AbortController + Map of resolvers) and the SDK `query()` async iterator alive indefinitely in the `activeSessions` Map. Over time, this grows without bound.

2. **Conversation stuck in `waiting_for_user`:** When the promise never resolves, `updateConversationStatus(conversationId, "active")` at line 273 never executes, and the conversation row stays in `waiting_for_user` permanently. Neither the `completed` nor `failed` terminal states are reached.

The `AbortController` already exists on the session (line 140-142) and is checked in the streaming loop (`controller.signal.aborted` at line 302) and in the error handler (line 349), but it is never wired to the review gate promise. The disconnect handler in `ws-handler.ts` (lines 333-344) only cleans up the WebSocket session -- it does not call `controller.abort()` or resolve pending gates.

Pre-existing since MVP. Discovered during code review of PR #830.

## Proposed Solution

Wire the `AbortController.signal` into the review gate promise so disconnects and session aborts cause the promise to reject, allowing the agent session to clean up naturally through the existing error/finally paths.

### Approach: AbortSignal-linked promise with rejection

Wrap the review gate promise in a race with an abort listener on `controller.signal`:

1. **In `canUseTool` (agent-runner.ts, ~line 269):** Replace the bare `new Promise` with an abort-aware variant that rejects when `controller.signal` fires.

2. **In `ws-handler.ts` disconnect handler (~line 333):** After removing the WebSocket session, look up the `AgentSession` in `activeSessions` and call `session.abort.abort()`. This triggers the signal, which rejects the review gate promise, which propagates through the SDK, which exits the `for await` loop, which hits the `finally` block that deletes the session from `activeSessions`.

3. **Add a timeout as a safety net:** If neither the user nor a disconnect resolves the gate within a configurable duration (e.g., 5 minutes), reject the promise. This catches edge cases where the disconnect event is missed (e.g., server restart without clean WebSocket close).

### Why not just resolve with a default value?

Rejecting is safer than resolving with a synthetic selection:

- A rejection propagates through the SDK and reaches the catch/finally cleanup.
- A synthetic "Reject" selection would continue the agent turn with a fabricated user decision, potentially taking unwanted actions.

### Research Insights

**Alternative approaches considered and rejected:**

- **`AbortSignal.timeout(timeoutMs)` + `AbortSignal.any([sessionSignal, timeoutSignal])`:** Node 22 provides these static methods to create timeout signals and combine signals. However, `AbortSignal.timeout()` creates an internal timer that is NOT cleared when the promise resolves normally -- it runs until expiry even after the user responds. This would hold a reference to the timer for 5 minutes on every review gate, wasting resources. The manual `setTimeout` + `clearTimeout` approach gives precise cleanup control.

- **`Promise.race()` with a separate timeout promise:** Simpler code but the losing promise (timeout or signal) leaks its listener/timer. The single-promise approach with internal cleanup avoids this.

**Best practices from Node.js docs (v22):**

- Use `{ once: true }` on `addEventListener("abort", ...)` to auto-remove after first fire (prevents listener accumulation if abort fires after resolve)
- Check `signal.aborted` synchronously before registering listeners (handles already-aborted signals)
- Use `error.name === 'AbortError'` to distinguish abort rejections from other errors in catch blocks
- Call `timer.unref()` on safety-net timers to prevent them from keeping the process alive during graceful shutdown

## Technical Considerations

- **AbortSignal.reason:** Use a typed reason (e.g., `new Error("Session aborted: user disconnected")`) so the catch block can distinguish disconnects from other errors and log appropriately. Node.js convention is to check `error.name === 'AbortError'` for abort-specific handling.
- **SDK behavior on canUseTool rejection:** Verify that a rejected promise from `canUseTool` terminates the SDK query cleanly (does not leave orphaned API calls). The SDK likely wraps the callback in a try/catch and treats rejection as a tool denial. If it does NOT catch, the rejection propagates to the `for await` loop catch block at line 348, which is acceptable -- the `finally` block at line 366 still runs.
- **Race condition:** The signal listener must be removed after the promise settles (user responds normally) to avoid memory leaks on the AbortController's listener list. Use `{ once: true }` on `addEventListener` AND explicit `removeEventListener` in the resolve path for belt-and-suspenders safety.
- **Timer lifecycle:** The `setTimeout` for the 5-minute safety net must: (a) be `clearTimeout`'d on resolve or abort, (b) call `.unref()` so it does not prevent clean process shutdown.
- **Duplicate `settingSources: []`:** Lines 191 and 198 both set `settingSources: []`. Remove the duplicate while in the file (separate cleanup, not part of the fix).
- **Error sanitizer:** Add safe message mappings for the disconnect and timeout errors so clients get clean messages if the error propagates to `sendToClient`.
- **Multiple conversations per user:** The `activeSessions` map uses `userId:conversationId` as key, but the `ws-handler.ts` disconnect handler only stores one `conversationId` per user. If the user starts a new session (superseding the old one), `current.conversationId` points to the latest conversation. The old conversation's agent session is already aborted at line 138 (`existing.abort.abort()`), so this is safe -- but the disconnect handler should still attempt to abort using the stored `conversationId`.
- **`abortSession` export pattern:** Export a function rather than the `activeSessions` map to maintain encapsulation. The function accepts `userId` and `conversationId`, looks up the session, and calls `abort()` with a descriptive reason.

## Acceptance Criteria

- [x] When a WebSocket disconnects, all pending review gate promises for that user reject within 1 second
- [x] The `AgentSession` is removed from `activeSessions` after disconnect (no leak)
- [x] The conversation status transitions to `failed` (not stuck on `waiting_for_user`)
- [x] A 5-minute timeout rejects the gate even without a disconnect event
- [x] Normal review gate flow (user responds) continues to work unchanged
- [x] The abort signal listener is cleaned up after normal resolution (no listener leak)
- [x] The timeout timer is cleaned up after normal resolution (no dangling timer)
- [x] The timeout timer uses `.unref()` so it does not block process shutdown
- [x] Duplicate `settingSources` entry removed from `query()` options

## Test Scenarios

- Given a user is in a review gate, when the WebSocket disconnects, then the review gate promise rejects within 1s and the agent session is cleaned up from `activeSessions`
- Given a user is in a review gate, when the user responds with a selection, then the promise resolves normally and the abort listener is removed
- Given a user is in a review gate, when the user responds with a selection, then the timeout timer is cleared (verify no dangling timers)
- Given a user is in a review gate, when 5 minutes elapse without response or disconnect, then the promise rejects with a timeout error
- Given a session is aborted (e.g., new session supersedes old one at line 138), when a review gate is pending, then the gate rejects via the abort signal
- Given the abort signal is already aborted when `abortableReviewGate` is called, then the promise rejects synchronously without registering listeners
- Given no review gate is pending, when a disconnect occurs, then cleanup proceeds without errors (no-op on empty resolvers map)
- Given the promise rejects (abort or timeout), then the resolver is deleted from `session.reviewGateResolvers` (no stale entries)

## MVP

### agent-runner.ts -- abort-aware review gate

```typescript
const REVIEW_GATE_TIMEOUT_MS = 5 * 60 * 1_000; // 5 minutes

// Helper: create a promise that rejects when the AbortSignal fires or timeout elapses
function abortableReviewGate(
  session: AgentSession,
  gateId: string,
  signal: AbortSignal,
  timeoutMs: number = REVIEW_GATE_TIMEOUT_MS,
): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    // Already aborted -- reject synchronously, skip listener registration
    if (signal.aborted) {
      reject(signal.reason || new Error("Session aborted"));
      return;
    }

    // Timeout safety net -- unref so it does not block process shutdown
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      session.reviewGateResolvers.delete(gateId);
      reject(new Error("Review gate timed out"));
    }, timeoutMs);
    timer.unref();

    // Abort signal listener
    const onAbort = () => {
      clearTimeout(timer);
      session.reviewGateResolvers.delete(gateId);
      reject(signal.reason || new Error("Session aborted"));
    };

    signal.addEventListener("abort", onAbort, { once: true });

    // Register the resolver -- when user responds, resolve and clean up
    session.reviewGateResolvers.set(gateId, (selection: string) => {
      clearTimeout(timer);
      signal.removeEventListener("abort", onAbort);
      resolve(selection);
    });
  });
}
```

### agent-runner.ts -- export abortSession

```typescript
// Export for ws-handler disconnect cleanup
export function abortSession(userId: string, conversationId: string): void {
  const key = sessionKey(userId, conversationId);
  const session = activeSessions.get(key);
  if (session) {
    session.abort.abort(new Error("Session aborted: user disconnected"));
  }
}
```

### agent-runner.ts -- replace bare promise (in canUseTool AskUserQuestion block)

Replace lines 269-271:

```typescript
// Before (leaks on disconnect):
const selection = await new Promise<string>((resolve) => {
  session.reviewGateResolvers.set(gateId, resolve);
});

// After (rejects on disconnect or timeout):
const selection = await abortableReviewGate(
  session,
  gateId,
  controller.signal,
);
```

### ws-handler.ts -- abort on disconnect

```typescript
// Add import at top of file:
import {
  startAgentSession,
  sendUserMessage,
  resolveReviewGate,
  abortSession,
} from "./agent-runner";

// Replace ws.on("close") handler:
ws.on("close", () => {
  clearTimeout(authTimer);
  if (pingInterval) clearInterval(pingInterval);
  if (userId) {
    const current = sessions.get(userId);
    if (current?.ws === ws) {
      sessions.delete(userId);
    }
    // Abort any running agent session for this user
    if (current?.conversationId) {
      abortSession(userId, current.conversationId);
    }
    console.log(`[ws] User ${userId} disconnected`);
  }
});
```

### error-sanitizer.ts -- safe messages for disconnect/timeout

```typescript
const KNOWN_SAFE_MESSAGES: Record<string, string> = {
  // ... existing entries ...
  "Review gate timed out":
    "The review prompt timed out. Please start a new session.",
  "Session aborted: user disconnected":
    "Your session was disconnected. Please reconnect to continue.",
};
```

### agent-runner.ts -- remove duplicate settingSources

Remove the duplicate `settingSources: []` at line 198. The entry at line 191 is sufficient.

## References

- Issue: #840
- Related PR: #830 (where the bug was discovered)
- Node.js v22 AbortController docs: `AbortSignal.timeout()`, `AbortSignal.any()`, `addEventListener("abort", ..., { once: true })`
- `apps/web-platform/server/agent-runner.ts` (lines 53-58, 136-145, 252-279, 348-368)
- `apps/web-platform/server/ws-handler.ts` (lines 29-36, 333-344)
- `apps/web-platform/server/error-sanitizer.ts`
- `apps/web-platform/lib/types.ts` (Conversation status type)
- `apps/web-platform/test/ws-protocol.test.ts`
- Learning: `knowledge-base/project/learnings/2026-03-20-safe-tools-allowlist-bypass-audit.md` (same module, confirms canUseTool callback pattern)
