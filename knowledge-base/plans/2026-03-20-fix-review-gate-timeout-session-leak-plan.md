---
title: "fix: review gate promise has no timeout, leaks agent sessions on disconnect"
type: fix
date: 2026-03-20
semver: patch
---

# fix: review gate promise has no timeout, leaks agent sessions on disconnect

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

## Technical Considerations

- **AbortSignal.reason:** Use a typed reason (e.g., `new Error("Session aborted: user disconnected")`) so the catch block can distinguish disconnects from other errors and log appropriately.
- **SDK behavior on canUseTool rejection:** Verify that a rejected promise from `canUseTool` terminates the SDK query cleanly (does not leave orphaned API calls). The SDK likely wraps the callback in a try/catch and treats rejection as a tool denial.
- **Race condition:** The signal listener must be removed after the promise settles (user responds normally) to avoid memory leaks on the AbortController's listener list. Use `{ once: true }` on `addEventListener` or explicit cleanup.
- **Duplicate `settingSources: []`:** Lines 191 and 198 both set `settingSources: []`. Remove the duplicate while in the file (separate cleanup, not part of the fix).
- **Error sanitizer:** Add a safe message mapping for the disconnect error so clients get a clean message if the error propagates to `sendToClient`.

## Acceptance Criteria

- [ ] When a WebSocket disconnects, all pending review gate promises for that user reject within 1 second
- [ ] The `AgentSession` is removed from `activeSessions` after disconnect (no leak)
- [ ] The conversation status transitions to `failed` (not stuck on `waiting_for_user`)
- [ ] A 5-minute timeout rejects the gate even without a disconnect event
- [ ] Normal review gate flow (user responds) continues to work unchanged
- [ ] The abort signal listener is cleaned up after normal resolution (no listener leak)
- [ ] Duplicate `settingSources` entry removed from `query()` options

## Test Scenarios

- Given a user is in a review gate, when the WebSocket disconnects, then the review gate promise rejects within 1s and the agent session is cleaned up from `activeSessions`
- Given a user is in a review gate, when the user responds with a selection, then the promise resolves normally and the abort listener is removed
- Given a user is in a review gate, when 5 minutes elapse without response or disconnect, then the promise rejects with a timeout error
- Given a session is aborted (e.g., new session supersedes old one at line 138), when a review gate is pending, then the gate rejects via the abort signal
- Given no review gate is pending, when a disconnect occurs, then cleanup proceeds without errors (no-op on empty resolvers map)

## MVP

### agent-runner.ts -- abort-aware review gate

```typescript
// Helper: create a promise that rejects when the AbortSignal fires
function abortableReviewGate(
  session: AgentSession,
  gateId: string,
  signal: AbortSignal,
  timeoutMs: number,
): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    // Timeout safety net
    const timer = setTimeout(() => {
      session.reviewGateResolvers.delete(gateId);
      reject(new Error("Review gate timed out"));
    }, timeoutMs);

    // Abort signal listener
    const onAbort = () => {
      clearTimeout(timer);
      session.reviewGateResolvers.delete(gateId);
      reject(signal.reason || new Error("Session aborted"));
    };

    if (signal.aborted) {
      clearTimeout(timer);
      reject(signal.reason || new Error("Session aborted"));
      return;
    }

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

### ws-handler.ts -- abort on disconnect

```typescript
// In the ws.on("close") handler, after removing from sessions:
// Import activeSessions or expose an abortSession() function from agent-runner.ts
import { abortSession } from "./agent-runner";

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

### error-sanitizer.ts -- safe message for disconnect/timeout

```typescript
const KNOWN_SAFE_MESSAGES: Record<string, string> = {
  // ... existing entries ...
  "Review gate timed out":
    "The review prompt timed out. Please start a new session.",
  "Session aborted":
    "Your session was disconnected. Please reconnect to continue.",
};
```

## References

- Issue: #840
- Related PR: #830 (where the bug was discovered)
- `apps/web-platform/server/agent-runner.ts` (lines 53-58, 136-145, 252-279, 348-368)
- `apps/web-platform/server/ws-handler.ts` (lines 29-36, 333-344)
- `apps/web-platform/server/error-sanitizer.ts`
- `apps/web-platform/lib/types.ts` (Conversation status type)
- `apps/web-platform/test/ws-protocol.test.ts`
