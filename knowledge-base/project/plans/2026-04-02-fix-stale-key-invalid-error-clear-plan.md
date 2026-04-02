---
title: "fix: clear stale key_invalid error card on remount"
type: fix
date: 2026-04-02
issue: "#1377"
---

# fix: clear stale key_invalid error card on remount

After a `key_invalid` error, the WebSocket is torn down and an error card is shown with an "Update key" link to `/dashboard/settings`. If the user navigates to settings, rotates their API key, and returns to the chat page, the stale error card can persist with no reconnect mechanism.

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 4 (Root Cause, Proposed Fix, Test Scenarios, Context)
**Research sources:** React docs (Context7), project learnings (3 relevant), codebase analysis (ws-client.ts, chat-page.test.tsx, error-states.test.tsx)

### Key Improvements

1. Validated bfcache concern with React lifecycle documentation -- frozen state restoration is a real edge case that the defensive clear addresses
2. Identified test coverage gap -- `chat-page.test.tsx` mock omits `lastError`/`reconnect`, existing `error-states.test.tsx` tests only cover the ErrorCard component, not the hook's state clearing behavior
3. Added `setDisconnectReason(undefined)` alongside `setLastError(null)` to prevent stale disconnect reason from previous session leaking into reconnection UI
4. Confirmed consistency with existing `reconnect()` callback which already clears both fields

### New Considerations Discovered

- The `ErrorCard`'s "Update key" link uses a plain `<a>` tag, not Next.js `<Link>` -- this means full page navigation on click, but browser back behavior varies (bfcache restore vs full reload)
- `chat-page.test.tsx` mock for `useWebSocket` is missing `lastError` and `reconnect` fields -- any test that renders the page with error state would silently get `undefined` for both, masking bugs
- The `messages` state should also be cleared on `conversationId` change to prevent stale messages from a prior conversation flashing briefly; however, this is out of scope for this fix (separate concern, tracked by conversation history fetch)

## Root Cause

When `key_invalid` fires (`ws-client.ts:226-234`), the handler:

1. Sets `lastError` to a structured error object
2. Calls `teardown()`, which sets `mountedRef.current = false`, clears timers, and closes the socket

The connection setup `useEffect` (line 359-371) runs on remount and resets `mountedRef.current = true`, then calls `connect()`. However, it does **not** clear `lastError`. While React `useState` reinitializes to `null` on a true unmount/remount cycle, the interaction between Next.js App Router client-side navigation, browser back-forward cache (bfcache), and React's component lifecycle can leave stale state in edge cases:

- **bfcache restoration**: The browser may restore the page from bfcache with frozen React state, including the non-null `lastError`. React does not re-run `useState` initializers on bfcache restore -- the component tree is restored as-is with all prior state values intact.
- **Next.js soft navigation**: When the `ErrorCard` links via a plain `<a>` tag (not `<Link>`), the return path varies -- browser back may trigger soft navigation depending on Next.js prefetch cache state.

The fix is defensive: explicitly clear `lastError` in the connection setup effect, ensuring a clean slate regardless of how the component arrives at its mounted state.

### Research Insights

**React useEffect lifecycle (from React docs):**

> When dependencies change, React first runs the cleanup function with old values, then the setup function with new values. After the component unmounts, React runs the cleanup function.

This confirms that resetting state at the top of the setup function is the correct pattern -- it runs after cleanup from the previous render cycle, providing a clean transition point.

**Alternative considered and rejected -- `key` prop reset:**

React's `key` prop can force full component remount, resetting all state. However, this is heavy-handed: it would destroy ALL state (messages, session, active streams), not just the error. The surgical `setLastError(null)` is the right granularity.

**Consistency with existing patterns:**

The `reconnect()` callback at line 404-410 already performs the same clear:

```typescript
const reconnect = useCallback(() => {
  setLastError(null);
  setDisconnectReason(undefined);
  mountedRef.current = true;
  backoffRef.current = INITIAL_BACKOFF;
  connect();
}, [connect]);
```

The fix makes the automatic reconnect path (on remount/conversationId change) mirror the manual reconnect path. The "clear stale state before starting new state" principle is established in this codebase (see: `abortActiveSession` pattern in ws-handler from learning `2026-03-27-ws-session-race-abort-before-replace.md`).

## Proposed Fix

Add `setLastError(null)` and `setDisconnectReason(undefined)` at the top of the connection setup `useEffect` in `ws-client.ts` (the effect at line 359 that depends on `[connect, conversationId]`). This clears any stale error when:

- The component mounts for the first time
- The `conversationId` changes (navigating between conversations)
- The `connect` function identity changes (unlikely given stable dependencies)

### `apps/web-platform/lib/ws-client.ts`

```typescript
// Before (line 359-371):
useEffect(() => {
  mountedRef.current = true;
  connect();
  return () => { /* cleanup */ };
}, [connect, conversationId]);

// After:
useEffect(() => {
  mountedRef.current = true;
  setLastError(null);             // Clear stale error from prior session
  setDisconnectReason(undefined); // Clear stale disconnect reason
  connect();
  return () => { /* cleanup */ };
}, [connect, conversationId]);
```

No changes needed in `page.tsx` -- the error card already renders conditionally based on `lastError`, so clearing it in the hook is sufficient.

## Acceptance Criteria

- [ ] After rotating an invalid API key and navigating back to chat, the error card is cleared
- [ ] The WebSocket attempts reconnection on remount (already works via `connect()` call; verified by `mountedRef.current = true` preceding it)
- [ ] Changing `conversationId` clears any prior error state
- [ ] The `reconnect()` callback still works correctly for manual retry (it already calls `setLastError(null)`)
- [ ] Existing error display behavior is unchanged for active sessions (errors still appear when the server sends them)

## Test Scenarios

- Given a `key_invalid` error has been received and the error card is displayed, when the connection setup `useEffect` re-runs (remount or `conversationId` change), then `lastError` is `null` and the error card is not rendered
- Given a `rate_limited` error is displayed, when the user navigates to a different conversation, then the error card is cleared on the new conversation
- Given no error has occurred, when the component mounts normally, then `lastError` remains `null` (no regression)
- Given an active WebSocket session with no errors, when the server sends an error message, then the error card still appears correctly

### Test Implementation Guidance

**File:** `apps/web-platform/test/error-states.test.tsx`

The existing test file covers `ErrorCard` component rendering and `WebSocketError` interface shape. The new tests should validate the hook's state clearing behavior. Since `useWebSocket` depends on browser WebSocket APIs and Supabase auth, test at the integration level by importing `NON_TRANSIENT_CLOSE_CODES` (already imported in idle-timeout tests in `ws-protocol.test.ts`) and verifying the exported constant shape, plus add a unit test for the reconnect-clears-error contract.

**Approach:** Add tests to `error-states.test.tsx` that verify:

1. The `reconnect()` function contract (clears lastError) -- test via mock
2. The connection setup effect contract (clears lastError on re-run) -- test via mock

The existing `chat-page.test.tsx` mock should be updated to include `lastError: null` and `reconnect: vi.fn()` in the `wsReturn` object to prevent future test gaps. This is a hygiene fix alongside the main change.

```typescript
// In chat-page.test.tsx, update the wsReturn mock:
let wsReturn = {
  messages: [],
  startSession: mockStartSession,
  sendMessage: mockSendMessage,
  sendReviewGateResponse: mockSendReviewGateResponse,
  status: "connected" as const,
  disconnectReason: undefined as string | undefined,
  lastError: null as import("@/lib/ws-client").WebSocketError | null,  // ADD
  reconnect: vi.fn(),                                                    // ADD
  routeSource: null as "auto" | "mention" | null,
  activeLeaderIds: [] as string[],
};
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- client-side state management bug fix.

## Context

- **Issue**: #1377
- **Milestone**: Phase 2: Secure for Beta
- **Labels**: priority/p3-low, code-review
- **Effort**: Small (two line addition in one file, plus test updates)
- **Related learning**: `knowledge-base/project/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md` -- original implementation of the `key_invalid` error handling
- **Related learning**: `knowledge-base/project/learnings/2026-03-27-websocket-close-code-routing-reconnect-loop.md` -- `teardown()` extraction and close-code routing
- **Related learning**: `knowledge-base/project/learnings/2026-03-27-ws-session-race-abort-before-replace.md` -- establishes "clear stale state before starting new state" pattern in ws-handler

## References

- `apps/web-platform/lib/ws-client.ts:226-234` -- `key_invalid` error handler
- `apps/web-platform/lib/ws-client.ts:359-371` -- connection setup useEffect (fix location)
- `apps/web-platform/lib/ws-client.ts:404-410` -- `reconnect()` callback (already clears `lastError`)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:160-169` -- error card rendering
- `apps/web-platform/components/ui/error-card.tsx` -- ErrorCard component
- `apps/web-platform/test/error-states.test.tsx` -- existing error state tests (extend with new tests)
- `apps/web-platform/test/chat-page.test.tsx` -- chat page tests (update mock to include `lastError`/`reconnect`)
- `apps/web-platform/test/ws-protocol.test.ts` -- WebSocket protocol tests (reference for import patterns)
- React docs: useEffect cleanup runs before setup on dependency change ([react.dev/reference/react/useEffect](https://react.dev/reference/react/useEffect))
