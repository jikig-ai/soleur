---
title: "sec: add basic WebSocket rate limiting (per-IP throttle)"
type: feat
date: 2026-03-29
semver: patch
---

# sec: add basic WebSocket rate limiting (per-IP throttle)

## Overview

Add in-memory rate limiting to the WebSocket server to prevent abuse via rapid connection attempts, concurrent connection exhaustion, and agent session spam. This is a Phase 2 security hardening item (#1046) -- defense-in-depth for the beta launch.

## Problem Statement / Motivation

The WebSocket server (`apps/web-platform/server/ws-handler.ts`) currently has no protection against:

1. **Connection flooding**: A single IP can open unlimited upgrade requests per second, exhausting server resources and `supabase.auth.getUser()` API calls.
2. **Concurrent connection abuse**: While the code enforces max 1 connection per authenticated user (line 447-449 -- supersedes old connections), there is no pre-auth throttle. An attacker can open thousands of unauthenticated sockets that each hold a 5-second auth timer.
3. **Agent session spam**: An authenticated user can call `start_session` repeatedly, spinning up unbounded Claude Agent SDK sessions. Each session costs API credits (user's BYOK key) and server memory.

The traffic path is: Client -> Cloudflare proxy -> Hetzner server -> Node.js HTTP server -> `ws` library upgrade. Cloudflare provides some DDoS protection, but application-layer throttling is needed for per-IP and per-user controls.

## Proposed Solution

Add three in-memory rate limiting layers, all implemented in `server/ws-handler.ts` (and a new `server/rate-limiter.ts` utility):

### Layer 1: IP-based connection throttle (pre-auth)

Reject WebSocket upgrade requests that exceed N connections per IP per time window. Applied in the `server.on("upgrade")` handler before `wss.handleUpgrade()`. Uses `cf-connecting-ip` header (Cloudflare proxy), falling back to `x-forwarded-for`, then `socket.remoteAddress`.

### Layer 2: Concurrent unauthenticated connection limit per IP

Track the number of open sockets per IP that have not yet authenticated. Reject new connections when the count exceeds a threshold. This prevents the 5-second auth timer from being weaponized.

### Layer 3: Agent session creation rate limit (per-user, post-auth)

Limit `start_session` messages to N per hour per authenticated user. Applied in `handleMessage()` for the `start_session` case. This is a sliding window counter keyed by `userId`.

### Architecture: In-memory vs external store

Use in-memory `Map`-based tracking. Rationale:

- Single-server deployment (one Hetzner VPS behind Cloudflare)
- No Redis or external cache in the current stack
- Counters reset on server restart -- acceptable for beta; the restart itself clears abuse state
- If the deployment scales to multiple servers, migrate to Redis-backed rate limiting (out of scope)

## Technical Considerations

### IP extraction behind Cloudflare

The server sits behind Cloudflare proxy (confirmed by `infra/firewall.tf` and the heartbeat comment). IP extraction priority:

1. `cf-connecting-ip` -- set by Cloudflare, most reliable
2. `x-forwarded-for` -- first entry (client IP)
3. `req.socket.remoteAddress` -- fallback (will be Cloudflare edge IP)

The `req` object is available in the `server.on("upgrade")` callback. The emit side already passes `req` (`wss.emit("connection", ws, req)`), but the `wss.on("connection")` handler signature currently only accepts `(ws: WebSocket)` -- it must be updated to accept a second `req: IncomingMessage` parameter to access IP headers.

### Rejection mechanism distinction

Layer 1 (connection throttle) rejects **before** the WebSocket upgrade completes -- it responds at the HTTP level with a 429 status and destroys the raw socket. Layer 2 (pending connection limit) rejects **after** the upgrade -- it uses WS close code 4008. This distinction is intentional: pre-upgrade rejection cannot use WebSocket close codes because no WebSocket connection exists yet.

### New close code for rate limiting

Add `RATE_LIMITED: 4008` to `WS_CLOSE_CODES` in `lib/types.ts`. The client (`ws-client.ts`) should treat this as non-transient (no reconnect) and display a user-friendly message.

### Client-side impact

The `ws-client.ts` uses exponential backoff for reconnection (1s initial, 30s max). The rate limit close code must be added to `NON_TRANSIENT_CLOSE_CODES` to prevent reconnect storms -- a rate-limited client that immediately reconnects would make the problem worse.

### Rate limiter design

```typescript
// server/rate-limiter.ts
interface RateLimiterConfig {
  windowMs: number;      // Time window in milliseconds
  maxRequests: number;   // Max requests per window
}

class SlidingWindowCounter {
  // Map<key, timestamps[]>
  // Periodically prune expired entries to prevent memory leak
}
```

Cleanup: Use lazy eviction (prune expired entries on each `isAllowed()` call) instead of a periodic `setInterval` timer. This eliminates a background timer and is sufficient for the expected scale (tens of concurrent users). If profiling shows lazy eviction adds measurable latency, switch to a periodic sweep with `setInterval().unref()`.

### Proposed limits (configurable via environment variables)

| Limit | Default | Env Var | Rationale |
|---|---|---|---|
| WS upgrades per IP per minute | 20 | `WS_RATE_LIMIT_CONNECTIONS_PER_MIN` | Generous for normal use (page reload, tab switch); blocks rapid scripted connections |
| Max unauthenticated sockets per IP | 5 | `WS_RATE_LIMIT_MAX_PENDING_PER_IP` | 5 simultaneous auth attempts is generous; an attacker script would hit this immediately |
| Agent sessions per user per hour | 30 | `WS_RATE_LIMIT_SESSIONS_PER_HOUR` | A busy user might start 10-15 sessions/hour; 30 provides headroom |

### Files to create/modify

| File | Action | Description |
|---|---|---|
| `apps/web-platform/server/rate-limiter.ts` | Create | `SlidingWindowCounter` class, IP extraction helper, periodic cleanup |
| `apps/web-platform/server/ws-handler.ts` | Modify | Integrate all three rate limiting layers |
| `apps/web-platform/lib/types.ts` | Modify | Add `RATE_LIMITED: 4008` close code, add `rate_limited` to `WSErrorCode` |
| `apps/web-platform/lib/ws-client.ts` | Modify | Add `RATE_LIMITED` to `NON_TRANSIENT_CLOSE_CODES` with user message |
| `apps/web-platform/test/rate-limiter.test.ts` | Create | Unit tests for `SlidingWindowCounter`, IP extraction |
| `apps/web-platform/test/ws-protocol.test.ts` | Modify | Add rate limit close code and NON_TRANSIENT_CLOSE_CODES assertions |

### Attack surface enumeration

All code paths that allow a WebSocket connection:

1. **HTTP upgrade on `/ws` path** (`server.on("upgrade")` in `ws-handler.ts` line 353) -- Layer 1 applies here
2. **WebSocket `connection` event** (`wss.on("connection")` line 367) -- Layer 2 applies here (track pending auth)
3. **`start_session` message handler** (`handleMessage` line 151) -- Layer 3 applies here
4. **`resume_session` message handler** (line 187) -- Does NOT create a new agent session, so Layer 3 does not apply. However, consider adding lightweight throttling to prevent resume spam in a future iteration.

Checked and not applicable:

- **REST API** (`/api/conversations/:id/messages`) -- read-only GET endpoint, not a rate limiting concern for this issue
- **Health endpoint** (`/health`) -- lightweight, no auth, not a concern

## Non-Goals

- Redis-backed distributed rate limiting (single server deployment)
- Rate limiting REST API endpoints (separate concern)
- Rate limiting the Next.js page routes (handled by Cloudflare)
- IP reputation / blocklist (Cloudflare handles this)
- `resume_session` throttling (low-risk, deferred)

## Acceptance Criteria

### Functional Requirements

- [ ] Rapid WebSocket connection attempts from the same IP (>20/min) are rejected with close code 4008
- [ ] More than 5 simultaneous unauthenticated WebSocket connections from the same IP are rejected
- [ ] More than 30 `start_session` messages per hour from the same authenticated user are rejected with an error message
- [ ] Rate limit thresholds are configurable via environment variables
- [ ] Client displays a user-friendly message when rate-limited (not an auto-reconnect loop)

### Non-Functional Requirements

- [ ] Rate limiter adds <1ms latency per connection check
- [ ] Memory usage grows proportionally to active IPs, not total historical connections (cleanup works)
- [ ] Server shutdown is not blocked by rate limiter timers (`.unref()` on all intervals)

### Quality Gates

- [ ] Unit tests for SlidingWindowCounter (window expiry, cleanup, edge cases)
- [ ] Unit tests for IP extraction (cf-connecting-ip, x-forwarded-for, remoteAddress)
- [ ] Integration tests verifying rate limit rejection at the ws-handler level
- [ ] All existing ws-protocol and ws-abort tests continue to pass

## Test Scenarios

### Acceptance Tests

- Given a single IP, when it attempts 21 WebSocket connections within 60 seconds, then the 21st connection is rejected with close code 4008
- Given a single IP with 5 pending (unauthenticated) connections, when a 6th connection attempt arrives, then it is rejected with close code 4008
- Given an authenticated user who has started 30 sessions in the past hour, when they send another `start_session` message, then they receive an error message indicating rate limiting
- Given a rate-limited IP, when 60 seconds pass without new attempts, then the next connection attempt succeeds

### Edge Cases

- Given a connection that authenticates and then disconnects, when counting pending connections, then the counter is decremented (no leak)
- Given the server restarts, when a previously rate-limited IP connects, then the connection succeeds (counters reset)
- Given two different IPs, when one is rate-limited, then the other is unaffected

### Client Behavior

- Given a client receives close code 4008, when the close event fires, then no automatic reconnection is attempted
- Given a client receives close code 4008, when the disconnect reason is displayed, then it shows "Too many requests. Please try again later."

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure security hardening with no user-facing UI changes, no vendor additions, and no legal document updates.

## Dependencies and Risks

- **Low risk**: In-memory rate limiting resets on deploy. This means a determined attacker could time attacks around deploys. Acceptable for beta -- Cloudflare provides the persistent layer.
- **Low risk**: Shared IP (corporate NAT, VPN) could cause false positives. The 20/min connection limit is generous enough to avoid this in practice. If reported, increase the limit or add an allowlist.
- **No new dependencies**: Pure TypeScript implementation using `Map` and `Date.now()`. No npm packages needed.

## References and Research

### Internal References

- WebSocket handler: `apps/web-platform/server/ws-handler.ts`
- Server entry: `apps/web-platform/server/index.ts`
- Agent runner: `apps/web-platform/server/agent-runner.ts`
- Client WS hook: `apps/web-platform/lib/ws-client.ts`
- Close codes: `apps/web-platform/lib/types.ts`
- Infrastructure: `apps/web-platform/infra/firewall.tf` (Cloudflare proxy confirmed)
- Existing tests: `apps/web-platform/test/ws-protocol.test.ts`, `test/ws-abort.test.ts`

### External References

- [Cloudflare CF-Connecting-IP header](https://developers.cloudflare.com/fundamentals/reference/http-request-headers/#cf-connecting-ip)
- [WebSocket close codes registry (4000-4999 application-reserved)](https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/code)
- GitHub issue: #1046
