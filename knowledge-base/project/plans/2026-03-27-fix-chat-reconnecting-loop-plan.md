---
title: "fix: stop chat interface reconnecting loop on non-transient close codes"
type: fix
date: 2026-03-27
---

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

The `CloseEvent` provides `code` and `reason` fields. Use these to branch:

- **4001, 4003 (auth failures):** Set status to `"disconnected"`, do NOT reconnect, redirect to `/login`.
- **4004 (T&C not accepted):** Set status to `"disconnected"`, do NOT reconnect, redirect to `/accept-terms`.
- **4002 (superseded):** Set status to `"disconnected"`, do NOT reconnect (the other tab has the connection).
- **4005 (internal error):** Set status to `"disconnected"`, do NOT reconnect. Display an error state.
- **All other codes (including 1006, 1001, undefined):** Reconnect with exponential backoff (preserve current behavior).

### 2. Update the `StatusIndicator` component to show actionable feedback

When status is `"disconnected"` due to a non-transient error, show a message that tells the user what happened instead of a generic "Disconnected" dot. Add an optional `disconnectReason` field to the hook return type.

### 3. Add `reason` to `CloseEvent` type handling

The `ws.onclose` callback receives a `CloseEvent` with `code` and `reason`. Update the handler signature to destructure these fields.

## Acceptance Criteria

- [ ] WebSocket close code 4001/4003 redirects user to `/login` instead of reconnecting
- [ ] WebSocket close code 4004 redirects user to `/accept-terms` instead of reconnecting
- [ ] WebSocket close code 4002 sets status to `"disconnected"` without reconnecting
- [ ] WebSocket close code 4005 sets status to `"disconnected"` with error feedback
- [ ] Normal disconnects (code 1006, 1001, undefined) still trigger exponential backoff reconnect
- [ ] Reconnect timer is properly cleared when a non-transient close code is received
- [ ] The `key_invalid` redirect in the message handler (existing) continues to work

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- client-side bug fix in WebSocket reconnection logic.

## Test Scenarios

- Given a user with an expired session token, when they open the chat page, then the WebSocket closes with 4001 and the client redirects to `/login` instead of looping on "Reconnecting..."
- Given a user who has not accepted the latest T&C version, when they open the chat page, then the WebSocket closes with 4004 and the client redirects to `/accept-terms`
- Given a user who opens the chat in two tabs, when the second tab connects, then the first tab receives 4002 and shows "Disconnected" without attempting reconnection
- Given a user on a flaky network, when the connection drops (code 1006), then the client reconnects with exponential backoff (unchanged behavior)
- Given a server internal error (code 4005), when the WebSocket closes, then the client shows an error state and does not reconnect

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

## References

- WebSocket close codes: [RFC 6455 Section 7.4.1](https://www.rfc-editor.org/rfc/rfc6455#section-7.4.1)
- Related issue: prior fix in #730 (CWE-598 first-message auth migration)
