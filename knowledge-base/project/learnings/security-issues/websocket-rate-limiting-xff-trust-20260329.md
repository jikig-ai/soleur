---
module: WebPlatform
date: 2026-03-29
problem_type: security_issue
component: authentication
symptoms:
  - "No rate limiting on WebSocket upgrade requests"
  - "Unbounded agent session creation per user"
  - "x-forwarded-for header trusted without Cloudflare validation"
root_cause: missing_validation
resolution_type: code_fix
severity: high
tags: [rate-limiting, websocket, ip-spoofing, cloudflare, defense-in-depth]
---

# WebSocket Rate Limiting: XFF Trust and Defense-in-Depth

## Problem

The WebSocket server (`apps/web-platform/server/ws-handler.ts`) had no protection against connection flooding, concurrent unauthenticated socket exhaustion, or agent session spam. The initial implementation trusted `x-forwarded-for` as a fallback for IP extraction, which would allow an attacker who bypasses Cloudflare to spoof IPs and evade all per-IP rate limiting.

## Solution

Three-layer in-memory rate limiting with Cloudflare-only IP trust:

1. **Layer 1 (pre-upgrade):** IP-based connection throttle using `SlidingWindowCounter` (20 req/min default). Rejects at HTTP 429 before WebSocket handshake.
2. **Layer 2 (pre-upgrade):** Concurrent unauthenticated connection cap per IP (5 default). Prevents 5-second auth timer weaponization.
3. **Layer 3 (post-auth):** Per-user session creation throttle (30/hour default). Keyed by userId, immune to IP rotation.

**Critical fix from review:** Removed `x-forwarded-for` fallback in `extractClientIp()`. When behind Cloudflare, absence of `cf-connecting-ip` means traffic bypassed the proxy — trusting XFF in that case allows IP spoofing. Fall through to `req.socket.remoteAddress` instead.

**Other review fixes:**

- Added periodic `prune()` intervals (60s for connections, 300s for sessions) to prevent unbounded memory growth from stale entries
- Fixed `Retry-After` header to use a fixed value (120) instead of leaking exact window config (CWE-209)
- Replaced `Array.filter` with in-place compaction to eliminate per-call GC pressure

## Key Insight

When behind a reverse proxy (Cloudflare), do NOT trust `x-forwarded-for` as a fallback — it is spoofable when traffic bypasses the proxy. Only trust the proxy's own header (`cf-connecting-ip`). The fallback should be `remoteAddress` (TCP-level, not spoofable). This applies to any Cloudflare-proxied service, not just WebSocket.

## Session Errors

1. **Frozen lockfile rejection during worktree setup** — `bun install --frozen-lockfile` failed because lockfile had changes. Recovery: ran `bun install` without the flag. **Prevention:** The worktree-manager script should detect lockfile drift and fall back to non-frozen install automatically.

2. **Plan prescribed lazy-only eviction, review overrode it** — The plan's "lazy eviction over periodic timer" decision was correct for simplicity but missed the unbounded memory growth vector. Three reviewers (security, performance, architecture) independently flagged it. Recovery: added periodic `prune()` after review. **Prevention:** When a plan makes a "no background timer" decision for rate limiters, explicitly analyze the memory growth profile under adversarial conditions (IP rotation, botnet) in the plan itself.

3. **Plan Layer 2 placement diverged from implementation** — Plan said Layer 2 rejects "after the upgrade using WS close code 4008", but implementation moved it pre-upgrade for efficiency. This left `RATE_LIMITED: 4008` close code defined but never produced by the server. **Prevention:** When diverging from plan during implementation, update the plan document to reflect the actual architecture and remove or justify any dead code.

## Tags

category: security-issues
module: WebPlatform
