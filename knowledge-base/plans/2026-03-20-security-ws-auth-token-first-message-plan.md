---
title: "security: move WebSocket auth token from URL query string to first message"
type: fix
date: 2026-03-20
semver: patch
---

# security: move WebSocket auth token from URL query string to first message

## Overview

The Supabase access token is currently passed in the WebSocket URL query string (`ws-client.ts:48`). Tokens in URL query strings are logged by web server access logs, Cloudflare edge logs, browser history, and proxy servers -- creating multiple credential leakage vectors. Move authentication to the first WebSocket message sent after connection is established.

## Problem Statement / Motivation

**Current implementation** (`ws-client.ts:48`):

```typescript
return `${proto}://${window.location.host}/ws?token=${token}`;
```

**Server-side extraction** (`ws-handler.ts:58`):

```typescript
const { query } = parse(req.url || "", true);
const token = query.token as string | undefined;
```

The token appears in:

1. **Cloudflare edge logs** -- the app is proxied through Cloudflare (`infra/dns.tf` confirms `proxied = true`); Cloudflare logs full request URLs including query parameters
2. **Node.js access logs** -- `ws-handler.ts:250` logs `req.url?.split("?")[0]` (currently stripped, but any future logging change could expose it)
3. **Browser history** -- WebSocket URLs with query params may appear in browser dev tools network tab and can be exported
4. **Proxy/CDN caches** -- any intermediate proxy that logs request URLs captures the token

This is a standard OWASP finding: [CWE-598 (Use of GET Request Method With Sensitive Query Strings)](https://cwe.mitre.org/data/definitions/598.html).

## Proposed Solution

Replace query-string auth with a first-message auth handshake:

1. **Client connects without token in URL** -- just `wss://host/ws`
2. **Client sends `{ type: "auth", token: "..." }` as the first message** after `onopen`
3. **Server buffers all non-auth messages** until auth completes (or closes the connection after a timeout)
4. **Server validates token**, then transitions to authenticated state for that connection
5. **Server sends `{ type: "auth_ok" }` or closes with `4001 Unauthorized`**

### Protocol change

Add two new message types to `WSMessage` union in `types.ts`:

- `{ type: "auth"; token: string }` -- client-to-server only
- `{ type: "auth_ok" }` -- server-to-client only (confirmation)

### Connection state machine

```text
CONNECTED (unauthenticated)
  |
  |-- receives { type: "auth", token } --> validate token
  |     |-- valid   --> AUTHENTICATED, send { type: "auth_ok" }, process queued messages
  |     |-- invalid --> close(4001, "Unauthorized")
  |
  |-- receives non-auth message --> close(4003, "Auth required")
  |
  |-- AUTH_TIMEOUT (5s) exceeded --> close(4001, "Auth timeout")
```

## Technical Considerations

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/lib/types.ts` | Add `auth` and `auth_ok` message types to `WSMessage` union |
| `apps/web-platform/lib/ws-client.ts` | Remove token from URL; send `auth` message in `onopen`; wait for `auth_ok` before setting status to `connected` |
| `apps/web-platform/server/ws-handler.ts` | Move auth from `authenticateConnection` (upgrade-time) to message handler; add pending-auth state with timeout |
| `apps/web-platform/test/ws-protocol.test.ts` | Update URL construction tests; add auth message tests; add auth timeout test |
| `apps/web-platform/test/middleware.test.ts` | Update `/ws?token=abc` test case (query param no longer expected) |

### Auth timeout

A 5-second timeout prevents unauthenticated connections from lingering. The timeout starts when the WebSocket connection opens and fires if no valid `auth` message arrives. This is important because `noServer: true` mode means the HTTP upgrade has no built-in auth gate.

### Backward compatibility

This is a breaking protocol change, but both client and server are deployed atomically (same Docker image, same deployment), so there is no version skew risk. No external consumers of the WebSocket API exist.

### Connection flow change

**Before:**

1. Client gets token from Supabase
2. Client opens `wss://host/ws?token=TOKEN`
3. Server validates token during HTTP upgrade
4. Server registers session
5. Client receives `onopen`, sets status to `connected`

**After:**

1. Client gets token from Supabase
2. Client opens `wss://host/ws` (no token in URL)
3. Server accepts connection in `pending_auth` state, starts 5s timeout
4. Client receives `onopen`, sends `{ type: "auth", token: "TOKEN" }`
5. Server validates token, registers session, sends `{ type: "auth_ok" }`
6. Client receives `auth_ok`, sets status to `connected`

### Reconnection behavior

The existing reconnect logic in `ws-client.ts` (exponential backoff with `connect()`) continues to work -- each `connect()` call opens a new WebSocket and sends `auth` in `onopen`. No changes to backoff logic needed.

### Security: server-side log scrubbing

The existing `req.url?.split("?")[0]` pattern in the warning log (`ws-handler.ts:250`) becomes moot since the URL no longer contains the token. However, the auth message content must NOT be logged. The existing `console.log` on line 116 (`[ws] Message from ${userId}: ${msg.type}`) only logs the message type, which is safe.

## Acceptance Criteria

- [ ] WebSocket URL no longer contains `?token=` parameter (`ws-client.ts`)
- [ ] Client sends `{ type: "auth", token }` as first message after `onopen` (`ws-client.ts`)
- [ ] Client waits for `auth_ok` before setting status to `connected` (`ws-client.ts`)
- [ ] Server validates auth from first message, not from URL query (`ws-handler.ts`)
- [ ] Server closes connection with `4001` if no auth message received within 5 seconds (`ws-handler.ts`)
- [ ] Server closes connection with `4003` if first non-auth message received before auth (`ws-handler.ts`)
- [ ] `WSMessage` type union includes `auth` and `auth_ok` variants (`types.ts`)
- [ ] All existing tests pass; new tests cover auth handshake protocol (`test/ws-protocol.test.ts`)
- [ ] No token appears in any server-side log output

## Test Scenarios

### Acceptance Tests

- Given a valid Supabase session, when the client connects to `/ws` and sends `{ type: "auth", token }`, then the server responds with `{ type: "auth_ok" }` and the client status becomes `connected`
- Given an invalid or expired token, when the client sends `{ type: "auth", token }`, then the server closes the connection with code `4001` and the client enters reconnect mode
- Given a connected but unauthenticated WebSocket, when the client sends `{ type: "chat", content: "hello" }` before auth, then the server closes with code `4003`
- Given a connected but unauthenticated WebSocket, when 5 seconds elapse without an auth message, then the server closes with code `4001`

### Regression Tests

- Given the fix is deployed, when examining the WebSocket URL in browser dev tools, then no token appears in the URL or query parameters
- Given the existing reconnect logic, when a connection drops and reconnects, then the auth handshake completes successfully on the new connection

### Edge Cases

- Given a race condition where auth times out just as the auth message arrives, then the connection is cleanly closed without crash
- Given the user has no Supabase session (null token), then the client sends `{ type: "auth", token: "" }` and the server rejects with `4001`

## Non-Goals

- Implementing a one-time ticket/nonce system (the first-message approach is sufficient for this threat model)
- Adding Sec-WebSocket-Protocol header auth (non-standard, poor browser support for custom protocols)
- Encrypting the WebSocket payload (TLS/wss already covers transport encryption)

## Dependencies and Risks

- **Low risk:** Both client and server deploy atomically. No API consumers exist outside the monorepo.
- **Cloudflare WebSocket support:** Cloudflare proxies WebSocket connections transparently after the HTTP upgrade. Moving auth to the message layer has no impact on Cloudflare's WebSocket proxy behavior.
- **Session token expiry:** Supabase access tokens are short-lived (default 1 hour). The auth handshake does not change token lifecycle -- the client still gets the token from `supabase.auth.getSession()` before each connection.

## References and Research

### Internal References

- `apps/web-platform/lib/ws-client.ts:48` -- current token-in-URL pattern
- `apps/web-platform/server/ws-handler.ts:52-70` -- current `authenticateConnection` function
- `apps/web-platform/lib/types.ts:14-22` -- `WSMessage` type union
- `apps/web-platform/test/ws-protocol.test.ts:127-142` -- URL construction tests to update
- `apps/web-platform/middleware.ts:4` -- `/ws` is in PUBLIC_PATHS (remains unchanged)
- `knowledge-base/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md` -- related WebSocket protocol learning

### External References

- [CWE-598: Use of GET Request Method With Sensitive Query Strings](https://cwe.mitre.org/data/definitions/598.html)
- [OWASP: Sensitive Data in Query Strings](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html)
- GitHub issue: #730

### Related Work

- PR #722 (issue #679) -- discovered during code review of this PR
- Issue #731 -- related WebSocket error sanitization
