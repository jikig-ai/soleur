---
title: "sec: add basic WebSocket rate limiting (per-IP throttle)"
type: feat
date: 2026-03-29
semver: patch
deepened: 2026-03-29
---

# sec: add basic WebSocket rate limiting (per-IP throttle)

## Enhancement Summary

**Deepened on:** 2026-03-29
**Sections enhanced:** 5 (Proposed Solution, IP Extraction, Rate Limiter Design, Test Scenarios, Acceptance Criteria)
**Research sources:** Web search (rate limiting patterns, Cloudflare headers), institutional learnings (review-gate validation, error sanitization, attack surface enumeration)

### Key Improvements

1. Added concrete `SlidingWindowCounter` implementation with lazy eviction and `Date.now()` monotonic clock consideration
2. Added IP spoofing prevention guidance -- validate `cf-connecting-ip` is only trusted when request arrives from Cloudflare IP ranges (or Cloudflare Tunnel)
3. Added Retry-After header pattern for HTTP 429 responses (Layer 1)
4. Added logging/observability recommendations (Sentry breadcrumbs for rate limit events)
5. Incorporated three institutional learnings: defense-in-depth pattern (review-gate), error sanitization (CWE-209), attack surface enumeration convention

### New Considerations Discovered

- `x-forwarded-for` can contain multiple comma-separated IPs; must extract only the first (leftmost) entry
- Lazy eviction should use `Array.prototype.filter` not in-place splice to avoid O(n) shifts
- Layer 3 error messages must go through `sanitizeErrorForClient` (existing pattern from CWE-209 learning)
- Consider adding Sentry breadcrumbs for rate limit rejections to enable abuse pattern detection

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

1. `cf-connecting-ip` -- set by Cloudflare, contains a single IP, most reliable
2. `x-forwarded-for` -- extract the **first** (leftmost) entry only; this header can contain multiple comma-separated IPs (e.g., `client, proxy1, proxy2`)
3. `req.socket.remoteAddress` -- fallback (will be Cloudflare edge IP in production)

The `req` object is available in the `server.on("upgrade")` callback. The emit side already passes `req` (`wss.emit("connection", ws, req)`), but the `wss.on("connection")` handler signature currently only accepts `(ws: WebSocket)` -- it must be updated to accept a second `req: IncomingMessage` parameter to access IP headers.

#### Research Insights: IP extraction

**Trust boundary:** The `cf-connecting-ip` header is set by Cloudflare and cannot be spoofed by end users when traffic flows through Cloudflare proxy. However, if the origin server is directly accessible (bypassing Cloudflare), an attacker could forge this header. The Hetzner firewall restricts HTTP to `0.0.0.0/0` (including Cloudflare IPs), but for defense-in-depth, consider restricting HTTP ingress to [Cloudflare IP ranges](https://www.cloudflare.com/ips/) in a future hardening pass. The current Cloudflare Tunnel setup already provides this guarantee since traffic never hits the origin directly.

**Implementation detail for `x-forwarded-for` parsing:**

```typescript
function extractFirstForwardedIp(header: string | undefined): string | undefined {
  if (!header) return undefined;
  const first = header.split(",")[0]?.trim();
  return first || undefined;
}
```

**References:**

- [Cloudflare HTTP headers documentation](https://developers.cloudflare.com/fundamentals/reference/http-headers/)
- [Restoring original visitor IPs](https://developers.cloudflare.com/support/troubleshooting/restoring-visitor-ips/restoring-original-visitor-ips/)

### Rejection mechanism distinction

Layer 1 (connection throttle) rejects **before** the WebSocket upgrade completes -- it responds at the HTTP level with a 429 status (with `Retry-After` header per RFC 6585) and destroys the raw socket. Layer 2 (pending connection limit) rejects **after** the upgrade -- it uses WS close code 4008. This distinction is intentional: pre-upgrade rejection cannot use WebSocket close codes because no WebSocket connection exists yet.

Layer 3 (session creation) rejects at the application message level -- it sends a `{ type: "error", message: "..." }` WebSocket message. The error message must go through `sanitizeErrorForClient()` (per the CWE-209 learning in `knowledge-base/project/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md`) to avoid leaking internal rate limit configuration details.

### New close code for rate limiting

Add `RATE_LIMITED: 4008` to `WS_CLOSE_CODES` in `lib/types.ts`. The client (`ws-client.ts`) should treat this as non-transient (no reconnect) and display a user-friendly message.

### Client-side impact

The `ws-client.ts` uses exponential backoff for reconnection (1s initial, 30s max). The rate limit close code must be added to `NON_TRANSIENT_CLOSE_CODES` to prevent reconnect storms -- a rate-limited client that immediately reconnects would make the problem worse.

### Rate limiter design

```typescript
// server/rate-limiter.ts
export interface RateLimiterConfig {
  windowMs: number;      // Time window in milliseconds
  maxRequests: number;   // Max requests per window
}

export class SlidingWindowCounter {
  private windows: Map<string, number[]>;  // key -> sorted timestamps
  private config: RateLimiterConfig;

  constructor(config: RateLimiterConfig) {
    this.windows = new Map();
    this.config = config;
  }

  /** Check if a request is allowed and record it if so. */
  isAllowed(key: string): boolean {
    const now = Date.now();
    const cutoff = now - this.config.windowMs;

    // Lazy eviction: filter expired entries on every check
    const timestamps = this.windows.get(key);
    const valid = timestamps
      ? timestamps.filter((t) => t > cutoff)
      : [];

    if (valid.length >= this.config.maxRequests) {
      // Over limit -- still update the filtered list to free memory
      this.windows.set(key, valid);
      return false;
    }

    valid.push(now);
    this.windows.set(key, valid);
    return true;
  }

  /** Remove keys with zero active entries (call periodically or on demand). */
  prune(): void {
    const now = Date.now();
    const cutoff = now - this.config.windowMs;
    for (const [key, timestamps] of this.windows) {
      const valid = timestamps.filter((t) => t > cutoff);
      if (valid.length === 0) {
        this.windows.delete(key);
      } else {
        this.windows.set(key, valid);
      }
    }
  }
}
```

Cleanup: Use lazy eviction (prune expired entries on each `isAllowed()` call) instead of a periodic `setInterval` timer. This eliminates a background timer and is sufficient for the expected scale (tens of concurrent users). If profiling shows lazy eviction adds measurable latency, switch to a periodic sweep with `setInterval().unref()`.

#### Research Insights: rate limiter implementation

**Algorithm choice:** The sliding window log (tracking individual timestamps) is the right choice here over a sliding window counter (interpolating between fixed windows). At the expected scale (<100 concurrent IPs), the memory overhead of storing individual timestamps is negligible, and it provides exact rate limiting without the approximation error of window interpolation. For millions of keys, switch to a sliding window counter or token bucket.

**`Date.now()` considerations:** `Date.now()` is monotonic in practice on V8/Node.js, but NTP adjustments can cause backward jumps. For a rate limiter this is acceptable -- a backward jump would temporarily allow slightly more requests, which is a safe failure mode (permissive, not restrictive).

**Memory bound:** Each IP stores at most `maxRequests` timestamps (8 bytes each). For 20 requests/min across 1000 IPs: `1000 * 20 * 8 = 160KB` -- negligible.

**Retry-After header (Layer 1):** When rejecting with HTTP 429, include a `Retry-After` header indicating seconds until the client can retry. This is both RFC 6585 compliant and helps well-behaved clients back off:

```typescript
// In the upgrade handler, when rejecting:
const retryAfterSec = Math.ceil(config.windowMs / 1_000);
socket.write(
  `HTTP/1.1 429 Too Many Requests\r\nRetry-After: ${retryAfterSec}\r\nConnection: close\r\n\r\n`,
);
socket.destroy();
```

**References:**

- [Rate Limiting in Node.js (OneUpTime)](https://oneuptime.com/blog/post/2026-01-06-nodejs-rate-limiting-no-external-services/view)
- [How to Handle WebSocket Rate Limiting (OneUpTime)](https://oneuptime.com/blog/post/2026-01-24-websocket-rate-limiting/view)
- [Building a Production-Ready Rate Limiter (DEV)](https://dev.to/chengyixu/building-a-production-ready-rate-limiter-in-nodejs-47o3)

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

### Observability and logging

All three rate limiting layers should log rejections using the existing `createChildLogger("ws")` pattern. Use structured log fields for filtering:

```typescript
log.warn({ sec: true, ip, layer: "connection-throttle", remaining: 0 }, "Rate limited: connection throttle");
log.warn({ sec: true, ip, layer: "pending-limit", pending: count }, "Rate limited: too many pending connections");
log.warn({ sec: true, userId, layer: "session-limit", sessionsInWindow: count }, "Rate limited: session creation");
```

The `sec: true` field follows the existing security logging convention (see `agent-runner.ts` SubagentStart hook). This enables filtering rate limit events in Better Stack for abuse pattern detection.

Additionally, add Sentry breadcrumbs for rate limit events to correlate with other errors in the same user session:

```typescript
Sentry.addBreadcrumb({
  category: "rate-limit",
  message: `Layer ${layer} triggered for ${key}`,
  level: "warning",
});
```

### Institutional learnings applied

Three documented learnings from `knowledge-base/project/learnings/` are directly relevant:

1. **Defense-in-depth pattern** (`security-issues/review-gate-selection-validation-web-platform-20260327.md`): The review gate fix used a 3-layer pattern (transport guard, business logic validation, options co-location). This plan follows the same pattern: Layer 1 (transport/HTTP), Layer 2 (connection-level), Layer 3 (application message-level).

2. **Error sanitization / CWE-209** (`2026-03-20-websocket-error-sanitization-cwe-209.md`): All error messages sent to clients must go through `sanitizeErrorForClient()`. Layer 3's rate limit error message should be a fixed string (e.g., "Too many sessions. Please wait before starting a new session.") added to the `KNOWN_SAFE_MESSAGES` map in `error-sanitizer.ts`.

3. **Attack surface enumeration** (`2026-03-20-security-fix-attack-surface-enumeration.md`): Before implementing, enumerate ALL code paths that touch the security surface. The plan's attack surface section (4 entry points + 2 checked-not-applicable) follows this convention.

## Non-Goals

- Redis-backed distributed rate limiting (single server deployment)
- Rate limiting REST API endpoints (separate concern)
- Rate limiting the Next.js page routes (handled by Cloudflare)
- IP reputation / blocklist (Cloudflare handles this)
- `resume_session` throttling (low-risk, deferred)

## Acceptance Criteria

### Functional Requirements

- [x] Rapid WebSocket connection attempts from the same IP (>20/min) are rejected with close code 4008
- [x] More than 5 simultaneous unauthenticated WebSocket connections from the same IP are rejected
- [x] More than 30 `start_session` messages per hour from the same authenticated user are rejected with an error message
- [x] Rate limit thresholds are configurable via environment variables
- [x] Client displays a user-friendly message when rate-limited (not an auto-reconnect loop)
- [x] HTTP 429 responses include a `Retry-After` header (RFC 6585 compliance)
- [x] Rate limit rejections are logged with structured fields (`sec: true`, IP/userId, layer name)

### Non-Functional Requirements

- [x] Rate limiter adds <1ms latency per connection check
- [x] Memory usage grows proportionally to active IPs, not total historical connections (cleanup works)
- [x] Server shutdown is not blocked by rate limiter timers (`.unref()` on all intervals)

### Quality Gates

- [x] Unit tests for SlidingWindowCounter (window expiry, cleanup, edge cases)
- [x] Unit tests for IP extraction (cf-connecting-ip, x-forwarded-for, remoteAddress)
- [x] Integration tests verifying rate limit rejection at the ws-handler level
- [x] All existing ws-protocol and ws-abort tests continue to pass

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
- Given an IP with 19 connections in the past minute, when the 20th connection authenticates and closes, then a 21st connection attempt within the same window is still rejected (the window tracks attempts, not active connections)
- Given a `SlidingWindowCounter` with entries from 2 minutes ago, when `isAllowed()` is called, then the stale entries are evicted (lazy cleanup works)
- Given a request with `x-forwarded-for: "1.2.3.4, 5.6.7.8, 9.10.11.12"`, when extracting the client IP, then `1.2.3.4` is returned (first entry only)
- Given a request with `cf-connecting-ip` set AND `x-forwarded-for` set to a different IP, when extracting the client IP, then `cf-connecting-ip` takes priority

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
