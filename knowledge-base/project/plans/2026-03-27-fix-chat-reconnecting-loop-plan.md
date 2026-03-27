---
title: "fix: stop chat interface reconnecting loop on non-transient close codes"
type: fix
date: 2026-03-27
deepened: 2026-03-27
---

## Enhancement Summary

**Deepened on:** 2026-03-27
**Sections enhanced:** 5 (Root Cause, Proposed Fix, Acceptance Criteria, Test Scenarios, Implementation Notes)
**Research sources used:** MDN WebSocket/CloseEvent docs (Context7), RFC 6455, codebase learnings (3), security review, simplicity review

### Key Improvements

1. Added concrete TypeScript implementation with close code routing map and teardown helper
2. Identified `wasClean` property as additional signal for differentiating server-initiated vs network closures
3. Added edge cases: Cloudflare 1006 with reason text, concurrent tab race, redirect during async connect
4. Security hardening: redirect teardown pattern must mirror existing `key_invalid` pattern exactly to prevent phantom sessions (learning: TOCTOU race)

### New Considerations Discovered

- The `wasClean` property on `CloseEvent` distinguishes server-initiated closes (clean handshake, `wasClean: true`) from network drops (`wasClean: false`, code 1006). This provides a secondary signal when the code alone is ambiguous.
- Cloudflare can inject its own close codes (typically 1006) when it terminates idle or errored connections. The `reason` string may contain Cloudflare-specific text in these cases.
- The existing `key_invalid` redirect in the message handler (lines 184-192) establishes a teardown pattern (`mountedRef = false`, `clearTimeout`, `onclose = null`, `close()`, `redirect`). The new close code handler MUST use the same pattern for consistency and to prevent the reconnect loop (documented in TOCTOU learning).

# fix: Stop chat interface reconnecting loop on non-transient close codes

The command center chat interface gets stuck on "Reconnecting..." when the WebSocket connection is closed by the server for a non-transient reason (auth failure, T&C not accepted, auth timeout). The client treats every `onclose` event identically -- blind exponential-backoff reconnect -- which creates an infinite reconnect loop for errors that will never self-resolve.

## Root Cause

In `apps/web-platform/lib/ws-client.ts`, the `ws.onclose` handler (lines 231-243) unconditionally sets status to `"reconnecting"` and schedules a retry. It does not inspect the WebSocket close code or reason. The server uses application-level close codes to signal non-transient failures:

| Code | Reason | Correct Client Behavior |
|------|--------|------------------------|
| 4001 | Auth timeout / Unauthorized | Redirect to `/login` (session expired) |
| 4002 | Superseded by new connection | No action (expected when user opens a second tab) |
| 4003 | Auth required (malformed first message) | Redirect to `/login` (client bug) |
| 4004 | T&C not accepted | Redirect to `/accept-terms` |
| 4005 | Internal error | Show error, allow manual retry |
| 1006 | Abnormal closure (network drop) | Reconnect with backoff (current behavior) |
| Other | Unknown | Reconnect with backoff |

The client already handles `key_invalid` error codes for in-session errors (lines 184-192) but has no equivalent for connection-level failures that happen during the auth handshake before `auth_ok` is received.

## Proposed Fix

### 1. Add close code handling to `ws.onclose` in `ws-client.ts`

The `CloseEvent` provides `code`, `reason`, and `wasClean` fields ([MDN: CloseEvent](https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent)). Update the handler signature from `() => {}` to `(event) => {}` and branch on `event.code`:

- **4001, 4003 (auth failures):** Set status to `"disconnected"`, do NOT reconnect, redirect to `/login`.
- **4004 (T&C not accepted):** Set status to `"disconnected"`, do NOT reconnect, redirect to `/accept-terms`.
- **4002 (superseded):** Set status to `"disconnected"`, do NOT reconnect (the other tab has the connection).
- **4005 (internal error):** Set status to `"disconnected"`, do NOT reconnect. Display an error state.
- **All other codes (including 1006, 1001, undefined):** Reconnect with exponential backoff (preserve current behavior).

#### Research Insights

**Close code routing map pattern:**

Define a constant map to keep the routing logic declarative and testable:

```typescript
// Close codes where reconnecting will never succeed
const NON_TRANSIENT_CLOSE_CODES: Record<number, { action: "redirect" | "disconnect"; target?: string; reason: string }> = {
  4001: { action: "redirect", target: "/login", reason: "Session expired" },
  4002: { action: "disconnect", reason: "Superseded by another tab" },
  4003: { action: "redirect", target: "/login", reason: "Authentication required" },
  4004: { action: "redirect", target: "/accept-terms", reason: "Terms acceptance required" },
  4005: { action: "disconnect", reason: "Server error" },
};
```

**Teardown helper (reuse existing `key_invalid` pattern):**

The existing `key_invalid` handler at lines 184-192 establishes a proven teardown sequence. Extract this into a helper to avoid duplication:

```typescript
/** Permanently tear down the WebSocket -- prevents reconnect loop.
 *  Mirrors the key_invalid teardown pattern (lines 184-192). */
function teardown() {
  mountedRef.current = false;
  clearTimeout(reconnectTimerRef.current);
  if (wsRef.current) {
    wsRef.current.onclose = null; // prevent recursive reconnect
    wsRef.current.close();
  }
}
```

**Updated `onclose` handler:**

```typescript
ws.onclose = (event: CloseEvent) => {
  if (!mountedRef.current) return;

  const entry = NON_TRANSIENT_CLOSE_CODES[event.code];
  if (entry) {
    teardown();
    setStatus("disconnected");
    setDisconnectReason(entry.reason);
    if (entry.action === "redirect" && entry.target) {
      window.location.href = entry.target;
    }
    return;
  }

  // Transient failure -- reconnect with exponential backoff
  setStatus("reconnecting");
  const delay = backoffRef.current;
  backoffRef.current = Math.min(backoffRef.current * 2, MAX_BACKOFF);
  reconnectTimerRef.current = setTimeout(() => {
    if (mountedRef.current) connect();
  }, delay);
};
```

**`wasClean` as secondary signal:**

Per [MDN CloseEvent.wasClean](https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/wasClean), `wasClean` is `true` when the server sent a proper close frame (codes 4001-4005), and `false` for abnormal closures (code 1006, network drop). This can be logged for diagnostics but should not be the primary routing signal -- the numeric code is more specific.

**Edge case -- Cloudflare-injected 1006:** Cloudflare terminates idle WebSocket connections after 100s with code 1006. The existing server-side `ws.ping()` every 30s prevents this, but if a keepalive is missed (process stall, GC pause), the client will see 1006 and correctly reconnect.

### 2. Update the `StatusIndicator` component to show actionable feedback

When status is `"disconnected"` due to a non-transient error, show a message that tells the user what happened instead of a generic "Disconnected" dot. Add an optional `disconnectReason` field to the hook return type.

#### Research Insights

**Minimal state addition:**

Add a single `disconnectReason` state to the hook. This avoids over-engineering (no new types, no status sub-states):

```typescript
const [disconnectReason, setDisconnectReason] = useState<string | undefined>(undefined);
```

Return it from the hook:

```typescript
return { messages, startSession, sendMessage, sendReviewGateResponse, status, disconnectReason };
```

**StatusIndicator enhancement:**

```typescript
function StatusIndicator({
  status,
  disconnectReason,
}: {
  status: ConnectionStatus;
  disconnectReason?: string;
}) {
  // ... existing config ...
  return (
    <div className="flex items-center gap-2">
      <span className={`h-2 w-2 rounded-full ${color}`} />
      <span className="text-xs text-neutral-500">
        {status === "disconnected" && disconnectReason ? disconnectReason : label}
      </span>
    </div>
  );
}
```

### 3. Add `reason` to `CloseEvent` type handling

The `ws.onclose` callback receives a `CloseEvent` with `code` and `reason`. Update the handler signature from `() => {}` to `(event: CloseEvent) => {}`.

#### Research Insights

**Browser `WebSocket.onclose` typing:**

The browser `WebSocket` interface types `onclose` as `((this: WebSocket, ev: CloseEvent) => any) | null`. TypeScript will automatically infer the `CloseEvent` type when using the assignment form `ws.onclose = (event) => {}`. An explicit type annotation `(event: CloseEvent)` is recommended for clarity but not strictly required.

**No server-side changes needed:**

The `ws` library (server-side) `close` event callback has a different signature: `(code: number, reason: Buffer) => void`. The server already sends proper close codes. This fix is client-only.

## Acceptance Criteria

- [ ] WebSocket close code 4001/4003 redirects user to `/login` instead of reconnecting
- [ ] WebSocket close code 4004 redirects user to `/accept-terms` instead of reconnecting
- [ ] WebSocket close code 4002 sets status to `"disconnected"` without reconnecting
- [ ] WebSocket close code 4005 sets status to `"disconnected"` with error feedback
- [ ] Normal disconnects (code 1006, 1001, undefined) still trigger exponential backoff reconnect
- [ ] Reconnect timer is properly cleared when a non-transient close code is received
- [ ] The `key_invalid` redirect in the message handler (existing) continues to work
- [ ] The teardown sequence (mountedRef, clearTimeout, onclose=null, close) is consistent between `key_invalid` handler and new close code handler
- [ ] `disconnectReason` is displayed in the `StatusIndicator` when status is `"disconnected"`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- client-side bug fix in WebSocket reconnection logic.

## Test Scenarios

- Given a user with an expired session token, when they open the chat page, then the WebSocket closes with 4001 and the client redirects to `/login` instead of looping on "Reconnecting..."
- Given a user who has not accepted the latest T&C version, when they open the chat page, then the WebSocket closes with 4004 and the client redirects to `/accept-terms`
- Given a user who opens the chat in two tabs, when the second tab connects, then the first tab receives 4002 and shows "Disconnected" without attempting reconnection
- Given a user on a flaky network, when the connection drops (code 1006), then the client reconnects with exponential backoff (unchanged behavior)
- Given a server internal error (code 4005), when the WebSocket closes, then the client shows an error state and does not reconnect
- Given an in-session `key_invalid` error, when the server sends the error message, then the existing redirect to `/setup-key` still fires (regression guard)
- Given a user whose auth token validation takes >5s (TOCTOU race), when the auth timer fires and closes with 4001, then the client redirects to `/login` without registering a phantom session (tests the same TOCTOU scenario documented in the 2026-03-20 learning)

### Research Insights: Edge Cases

- **Concurrent tab race:** If a user opens two tabs simultaneously, both may be in `"connecting"` state. The first to authenticate supersedes the other (code 4002). The superseded tab should NOT show an error -- just a quiet "Disconnected" state with reason "Superseded by another tab".
- **Redirect during async `connect()`:** If `getWsUrlAndToken()` is in flight when a redirect fires from `onclose`, the `mountedRef.current = false` guard prevents the token-fetching callback from creating a new connection after the redirect.
- **Unknown future close codes:** If the server adds new 4xxx codes in the future, the default branch reconnects with backoff. This is the safer default -- new codes should be explicitly added to `NON_TRANSIENT_CLOSE_CODES` when introduced.

## Context

### Relevant Files

- `apps/web-platform/lib/ws-client.ts` -- Client-side WebSocket hook (primary fix target)
- `apps/web-platform/server/ws-handler.ts` -- Server-side close code definitions (reference only)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- Chat page UI (StatusIndicator update)

### Related Learnings

- `knowledge-base/project/learnings/2026-03-17-websocket-cloudflare-auth-debugging.md` -- Previous WebSocket auth fix (query param to first-message migration)
- `knowledge-base/project/learnings/2026-03-20-websocket-first-message-auth-toctou-race.md` -- TOCTOU race in auth timeout vs async validation
- `knowledge-base/project/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md` -- Typed error codes pattern for key_invalid redirect

### Implementation Notes

- The WebSocket `onclose` event in browsers provides a `CloseEvent` with numeric `code` and string `reason` properties. The current handler ignores both.
- The `4001` close code conflicts with the existing `AUTH_TIMEOUT_MS` timer (auth timeout) and token validation failure (unauthorized). Both use 4001 but have the same recovery action (redirect to `/login`), so this is acceptable.
- The server already logs close reasons (`ws.close(4001, "Auth timeout")`, etc.). The client can use these for debugging but should route on the numeric code, not string matching.

#### Research Insights

**Security: Teardown pattern consistency (from TOCTOU learning).**

The 2026-03-20 learning documents how a phantom session entry caused reconnect loops. The teardown sequence MUST be:

1. `mountedRef.current = false` -- prevents any async callbacks from mutating state
2. `clearTimeout(reconnectTimerRef.current)` -- cancels pending reconnect
3. `wsRef.current.onclose = null` -- prevents recursive onclose from `.close()`
4. `wsRef.current.close()` -- cleanly close the socket
5. `window.location.href = target` -- redirect (for redirect cases)

This sequence already exists in the `key_invalid` handler (lines 184-192). Extracting it into a `teardown()` helper prevents divergence.

**Simplicity: No new types or status sub-states needed.**

The fix adds one `useState<string | undefined>` for `disconnectReason` and one constant map for close code routing. No new TypeScript types, no changes to `ConnectionStatus`, no changes to `WSMessage`. The `NON_TRANSIENT_CLOSE_CODES` map is the only new abstraction -- it keeps the logic declarative and easy to extend when new server close codes are added.

**Performance: No impact.**

The `onclose` handler fires once per connection lifecycle. The close code lookup in a 5-entry `Record` is O(1). No new event listeners, no new timers, no new network requests.

## References

- WebSocket close codes: [RFC 6455 Section 7.4.1](https://www.rfc-editor.org/rfc/rfc6455#section-7.4.1)
- MDN CloseEvent: [CloseEvent API](https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent)
- MDN CloseEvent.code: [CloseEvent.code](https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/code) (codes 4000-4999 are private use / application-defined)
- MDN CloseEvent.wasClean: [CloseEvent.wasClean](https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/wasClean)
- Related issue: prior fix in #730 (CWE-598 first-message auth migration)
