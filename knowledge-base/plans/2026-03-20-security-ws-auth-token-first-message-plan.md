---
title: "security: move WebSocket auth token from URL query string to first message"
type: fix
date: 2026-03-20
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6 (Proposed Solution, Technical Considerations, Auth Timeout, Security, Test Scenarios, References)
**Research sources:** ws library docs (Context7), WebSocket security best practices (WebSocket.org, Invicti, VideoSDK), close code conventions (Discord, Twitch, Wazo), institutional learnings

### Key Improvements

1. Added concrete server-side implementation pattern using `ws` library's `noServer` mode with per-connection auth state
2. Added DoS mitigation analysis for unauthenticated connection flooding and rate limiting guidance
3. Added auth timeout race condition handling with `clearTimeout` guard pattern
4. Added future token renewal consideration as a documented non-goal with upgrade path

### New Considerations Discovered

- The `ws` library's recommended auth pattern uses HTTP upgrade rejection (current approach); first-message auth is intentionally trading that gate for log safety -- document this tradeoff
- Close codes 4000-4999 are application-reserved per RFC 6455; Discord uses 4003 for "Not Authenticated" (validates our choice)
- Origin header validation should be verified as part of this change (currently not checked)

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
3. **Server rejects non-auth messages** with close(4003) until auth completes (or closes the connection after a timeout)
4. **Server validates token**, then transitions to authenticated state for that connection
5. **Server sends `{ type: "auth_ok" }` or closes with `4001 Unauthorized`**

### Research Insights: Auth Approach Tradeoff

The `ws` library's [recommended authentication pattern](https://github.com/websockets/ws/blob/master/README.md) validates credentials during the HTTP upgrade and rejects with `401 Unauthorized` before the WebSocket connection is established. This is resource-efficient because the server never allocates per-connection state for unauthenticated clients.

First-message auth intentionally trades that gate for log safety: the server accepts the TCP connection and WebSocket upgrade without credentials, then authenticates via the first message. The tradeoff is that unauthenticated connections briefly consume server resources (socket, memory). The 5-second auth timeout mitigates this -- connections that do not authenticate are terminated before they can accumulate.

This tradeoff is acceptable because:
- The app is behind Cloudflare, which provides L7 DDoS protection
- The existing heartbeat interval (30s) already manages idle connections
- Supabase tokens are short-lived (1 hour default), limiting the window for stolen tokens

### Protocol change

Add two new message types to `WSMessage` union in `types.ts`:

- `{ type: "auth"; token: string }` -- client-to-server only
- `{ type: "auth_ok" }` -- server-to-client only (confirmation)

### Connection state machine

```text
CONNECTED (unauthenticated)
  |
  |-- receives { type: "auth", token } --> validate token
  |     |-- valid   --> AUTHENTICATED, send { type: "auth_ok" }
  |     |-- invalid --> close(4001, "Unauthorized")
  |
  |-- receives non-auth message --> close(4003, "Auth required")
  |
  |-- AUTH_TIMEOUT (5s) exceeded --> close(4001, "Auth timeout")
```

### Close code rationale

Close codes 4000-4999 are reserved for application use per [RFC 6455 Section 7.4.2](https://datatracker.ietf.org/doc/html/rfc6455#section-7.4.2). The chosen codes align with industry conventions:

| Code | Meaning | Precedent |
|------|---------|-----------|
| `4001` | Unauthorized (bad token or timeout) | Consistent with HTTP 401 semantics |
| `4003` | Not authenticated (message before auth) | [Discord uses 4003](https://discord.com/developers/docs/topics/opcodes-and-status-codes) for "Not Authenticated" |

## Technical Considerations

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/lib/types.ts` | Add `auth` and `auth_ok` message types to `WSMessage` union |
| `apps/web-platform/lib/ws-client.ts` | Remove token from URL; rename `getWsUrl` to reflect it also retrieves the token; send `auth` message in `onopen`; wait for `auth_ok` before setting status to `connected` |
| `apps/web-platform/server/ws-handler.ts` | Move auth from `authenticateConnection` (upgrade-time) to message handler; add pending-auth state with timeout; update exhaustive switch for `auth` (client-to-server) and `auth_ok` (server-only list) |
| `apps/web-platform/test/ws-protocol.test.ts` | Update URL construction tests; add auth message tests; add auth timeout test |
| `apps/web-platform/test/middleware.test.ts` | Update `/ws?token=abc` test case (query param no longer expected) |

### Server-side implementation pattern

The connection handler in `setupWebSocket` changes from authenticate-then-register to register-as-pending-then-authenticate:

```typescript
// ws-handler.ts -- connection handler (after change)
wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
  // No auth gate here -- auth moves to first message
  let authenticated = false;
  let userId: string | null = null;

  // Auth timeout: close if no auth message within 5 seconds
  const authTimer = setTimeout(() => {
    if (!authenticated) {
      ws.close(4001, "Auth timeout");
    }
  }, 5_000);

  ws.on("message", async (data) => {
    if (!authenticated) {
      // First message MUST be auth
      let msg: { type: string; token?: string };
      try {
        msg = JSON.parse(data.toString());
      } catch {
        ws.close(4003, "Auth required");
        clearTimeout(authTimer);
        return;
      }

      if (msg.type !== "auth" || !msg.token) {
        ws.close(4003, "Auth required");
        clearTimeout(authTimer);
        return;
      }

      // Validate token
      const result = await supabase.auth.getUser(msg.token);
      if (result.error || !result.data.user) {
        ws.close(4001, "Unauthorized");
        clearTimeout(authTimer);
        return;
      }

      // Auth success
      clearTimeout(authTimer);
      authenticated = true;
      userId = result.data.user.id;

      // Register session, set up heartbeat, etc.
      // ... (existing session registration logic)

      ws.send(JSON.stringify({ type: "auth_ok" }));
      return;
    }

    // Authenticated -- route to handleMessage
    handleMessage(userId!, data.toString()).catch(/* ... */);
  });

  ws.on("close", () => {
    clearTimeout(authTimer);
    // ... existing cleanup
  });
});
```

**Key pattern:** The `authenticated` boolean and `authTimer` are scoped to the closure of each connection. This avoids adding state to the `sessions` Map for unauthenticated connections.

### Auth timeout

A 5-second timeout prevents unauthenticated connections from lingering. The timeout starts when the WebSocket connection opens and fires if no valid `auth` message arrives. This is important because `noServer: true` mode means the HTTP upgrade has no built-in auth gate.

#### Research Insights: DoS Mitigation

With first-message auth, the server accepts unauthenticated WebSocket connections. An attacker could open many connections without sending auth messages. Defenses:

1. **Auth timeout (5s)** -- already in plan. Limits each unauthenticated connection to 5 seconds of resource consumption.
2. **Cloudflare rate limiting** -- the app is behind Cloudflare proxy (`proxied = true` in `dns.tf`), which provides connection rate limiting and DDoS mitigation at the edge.
3. **No session allocation before auth** -- the implementation pattern above keeps unauthenticated connections out of the `sessions` Map, so they consume only the raw WebSocket socket and the 5s timer.

**Not needed now (future consideration):** Server-side connection rate limiting per IP. Cloudflare handles this at the edge. If the app ever moves off Cloudflare, add `ws` connection counting in the `upgrade` handler.

### Auth timeout race condition

The timeout fires asynchronously. If the auth message arrives just as the timer fires, both the `ws.close(4001)` from the timer and the auth success path could execute. Guard with an `authenticated` boolean check:

```typescript
const authTimer = setTimeout(() => {
  if (!authenticated) {
    ws.close(4001, "Auth timeout");
  }
}, 5_000);
```

The `clearTimeout(authTimer)` in the auth success path prevents the timer from firing after successful auth. If the timer fires first, the `ws.close()` call initiates the closing handshake, and subsequent `ws.send()` calls are no-ops (the `ws` library silently drops sends on closing/closed sockets).

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

### Institutional Learning: Typed Error Codes Pattern

From `knowledge-base/learnings/2026-03-18-typed-error-codes-websocket-key-invalidation.md`: when adding new message types to the WebSocket protocol, use typed error classes (`instanceof`) instead of string matching. The existing `KeyInvalidError` pattern should be preserved -- the auth refactor must not break the `errorCode: "key_invalid"` detection path in `agent-runner.ts:265`. The `auth` and `auth_ok` types are protocol-level (handled before `handleMessage`), so they do not interact with the error code system.

## Acceptance Criteria

- [x] WebSocket URL no longer contains `?token=` parameter (`ws-client.ts`)
- [x] Client sends `{ type: "auth", token }` as first message after `onopen` (`ws-client.ts`)
- [x] Client waits for `auth_ok` before setting status to `connected` (`ws-client.ts`)
- [x] Server validates auth from first message, not from URL query (`ws-handler.ts`)
- [x] Server closes connection with `4001` if no auth message received within 5 seconds (`ws-handler.ts`)
- [x] Server closes connection with `4003` if first non-auth message received before auth (`ws-handler.ts`)
- [x] `WSMessage` type union includes `auth` and `auth_ok` variants (`types.ts`)
- [x] All existing tests pass; new tests cover auth handshake protocol (`test/ws-protocol.test.ts`)
- [x] No token appears in any server-side log output
- [x] `KeyInvalidError` / `errorCode: "key_invalid"` detection still works after refactor

## Test Scenarios

### Acceptance Tests

- Given a valid Supabase session, when the client connects to `/ws` and sends `{ type: "auth", token }`, then the server responds with `{ type: "auth_ok" }` and the client status becomes `connected`
- Given an invalid or expired token, when the client sends `{ type: "auth", token }`, then the server closes the connection with code `4001` and the client enters reconnect mode
- Given a connected but unauthenticated WebSocket, when the client sends `{ type: "chat", content: "hello" }` before auth, then the server closes with code `4003`
- Given a connected but unauthenticated WebSocket, when 5 seconds elapse without an auth message, then the server closes with code `4001`

### Regression Tests

- Given the fix is deployed, when examining the WebSocket URL in browser dev tools, then no token appears in the URL or query parameters
- Given the existing reconnect logic, when a connection drops and reconnects, then the auth handshake completes successfully on the new connection
- Given a user with an invalid API key, when the agent runner throws `KeyInvalidError`, then the client receives `errorCode: "key_invalid"` and redirects to `/setup-key`

### Edge Cases

- Given a race condition where auth times out just as the auth message arrives, then the connection is cleanly closed without crash (the `ws` library silently drops sends on closing sockets)
- Given the user has no Supabase session (null token), then the client sends `{ type: "auth", token: "" }` and the server rejects with `4001`
- Given the client sends malformed JSON as the first message, then the server closes with `4003` (not a crash)
- Given multiple rapid reconnections (exponential backoff), each connection completes the auth handshake independently

## Non-Goals

- Implementing a one-time ticket/nonce system (the first-message approach is sufficient for this threat model)
- Adding Sec-WebSocket-Protocol header auth (non-standard, poor browser support for custom protocols)
- Encrypting the WebSocket payload (TLS/wss already covers transport encryption)
- In-band token renewal (token refresh happens via Supabase client; on expiry the client reconnects with a fresh token)
- Origin header validation (worth auditing separately but not in scope for this credential-leakage fix)
- Server-side per-IP rate limiting (Cloudflare handles this at the edge)

## Dependencies and Risks

- **Low risk:** Both client and server deploy atomically. No API consumers exist outside the monorepo.
- **Cloudflare WebSocket support:** Cloudflare proxies WebSocket connections transparently after the HTTP upgrade. Moving auth to the message layer has no impact on Cloudflare's WebSocket proxy behavior.
- **Session token expiry:** Supabase access tokens are short-lived (default 1 hour). The auth handshake does not change token lifecycle -- the client still gets the token from `supabase.auth.getSession()` before each connection.
- **Auth timeout + Supabase latency:** The `supabase.auth.getUser()` call is an HTTP request to Supabase. If Supabase is slow (>5s), the auth timeout could fire before validation completes. Mitigation: the timeout only fires if `authenticated` is still false; if the Supabase call is in-flight, the closure's `authenticated` flag prevents the timeout from closing an about-to-be-authenticated connection. However, if Supabase is consistently >5s, connections will fail. This is acceptable -- if Supabase is that slow, the app is degraded regardless.

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
- [ws library: Client Authentication (noServer mode)](https://github.com/websockets/ws/blob/master/README.md)
- [WebSocket Authentication: Securing Real-Time Connections](https://www.videosdk.live/developer-hub/websocket/websocket-authentication)
- [WebSocket Security Hardening Guide](https://websocket.org/guides/security/)
- [WebSocket Close Codes Reference](https://websocket.org/reference/close-codes/)
- [RFC 6455 Section 7.4.2: Application Close Codes](https://datatracker.ietf.org/doc/html/rfc6455#section-7.4.2)
- GitHub issue: #730

### Related Work

- PR #722 (issue #679) -- discovered during code review of this PR
- Issue #731 -- related WebSocket error sanitization
