---
title: "fix: clear stale key_invalid error card on remount"
type: fix
date: 2026-04-02
issue: "#1377"
---

# fix: clear stale key_invalid error card on remount

After a `key_invalid` error, the WebSocket is torn down and an error card is shown with an "Update key" link to `/dashboard/settings`. If the user navigates to settings, rotates their API key, and returns to the chat page, the stale error card can persist with no reconnect mechanism.

## Root Cause

When `key_invalid` fires (`ws-client.ts:226-234`), the handler:

1. Sets `lastError` to a structured error object
2. Calls `teardown()`, which sets `mountedRef.current = false`, clears timers, and closes the socket

The connection setup `useEffect` (line 359-371) runs on remount and resets `mountedRef.current = true`, then calls `connect()`. However, it does **not** clear `lastError`. While React `useState` reinitializes to `null` on a true unmount/remount cycle, the interaction between Next.js App Router client-side navigation, browser back-forward cache (bfcache), and React's component lifecycle can leave stale state in edge cases:

- **bfcache restoration**: The browser may restore the page from bfcache with frozen React state, including the non-null `lastError`
- **Next.js soft navigation**: When the `ErrorCard` links via a plain `<a>` tag (not `<Link>`), the return path varies — browser back may trigger soft navigation depending on Next.js prefetch cache state

The fix is defensive: explicitly clear `lastError` in the connection setup effect, ensuring a clean slate regardless of how the component arrives at its mounted state.

## Proposed Fix

Add `setLastError(null)` at the top of the connection setup `useEffect` in `ws-client.ts` (the effect at line 359 that depends on `[connect, conversationId]`). This clears any stale error when:

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
  setLastError(null);          // Clear stale error from prior session
  setDisconnectReason(undefined); // Clear stale disconnect reason
  connect();
  return () => { /* cleanup */ };
}, [connect, conversationId]);
```

No changes needed in `page.tsx` — the error card already renders conditionally based on `lastError`, so clearing it in the hook is sufficient.

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

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- client-side state management bug fix.

## Context

- **Issue**: #1377
- **Milestone**: Phase 2: Secure for Beta
- **Labels**: priority/p3-low, code-review
- **Effort**: Small (single line addition in one file)
- **Related learning**: `knowledge-base/project/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md` — original implementation of the `key_invalid` error handling
- **Related learning**: `knowledge-base/project/learnings/2026-03-27-websocket-close-code-routing-reconnect-loop.md` — `teardown()` extraction and close-code routing

## References

- `apps/web-platform/lib/ws-client.ts:226-234` — `key_invalid` error handler
- `apps/web-platform/lib/ws-client.ts:359-371` — connection setup useEffect (fix location)
- `apps/web-platform/lib/ws-client.ts:404-410` — `reconnect()` callback (already clears `lastError`)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:160-169` — error card rendering
- `apps/web-platform/components/ui/error-card.tsx` — ErrorCard component
- `apps/web-platform/test/error-states.test.tsx` — existing error state tests
