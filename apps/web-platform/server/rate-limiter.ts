import type { IncomingMessage } from "http";
import * as Sentry from "@sentry/nextjs";
import { createChildLogger } from "./logger";

const log = createChildLogger("ws");

// ---------------------------------------------------------------------------
// Configuration (env-configurable with defaults from plan)
// ---------------------------------------------------------------------------

export const RATE_LIMIT_CONFIG = {
  /** Max WS upgrade requests per IP per window. */
  connectionsPerWindow: parseInt(
    process.env.WS_RATE_LIMIT_CONNECTIONS_PER_MIN ?? "20",
    10,
  ),
  /** Window duration for connection throttle (ms). */
  connectionWindowMs: 60_000,

  /** Max unauthenticated (pending-auth) sockets per IP. */
  maxPendingPerIp: parseInt(
    process.env.WS_RATE_LIMIT_MAX_PENDING_PER_IP ?? "5",
    10,
  ),

  /** Max agent sessions per user per window. */
  sessionsPerWindow: parseInt(
    process.env.WS_RATE_LIMIT_SESSIONS_PER_HOUR ?? "30",
    10,
  ),
  /** Window duration for session throttle (ms). */
  sessionWindowMs: 3_600_000,
} as const;

// ---------------------------------------------------------------------------
// SlidingWindowCounter — generic timestamp-based rate limiter
// ---------------------------------------------------------------------------

export interface RateLimiterConfig {
  windowMs: number;
  maxRequests: number;
}

export class SlidingWindowCounter {
  private windows: Map<string, number[]> = new Map();
  private config: RateLimiterConfig;

  constructor(config: RateLimiterConfig) {
    this.config = config;
  }

  /** Check if a request is allowed and record it if so. */
  isAllowed(key: string): boolean {
    const now = Date.now();
    const cutoff = now - this.config.windowMs;

    let timestamps = this.windows.get(key);
    if (timestamps) {
      // In-place compaction: avoids allocating a new array on every call.
      let write = 0;
      for (let i = 0; i < timestamps.length; i++) {
        if (timestamps[i] > cutoff) {
          timestamps[write++] = timestamps[i];
        }
      }
      timestamps.length = write;
    } else {
      timestamps = [];
      this.windows.set(key, timestamps);
    }

    if (timestamps.length >= this.config.maxRequests) {
      return false;
    }

    timestamps.push(now);
    return true;
  }

  /** Remove keys with zero active entries. */
  prune(): void {
    const now = Date.now();
    const cutoff = now - this.config.windowMs;
    for (const [key, timestamps] of this.windows) {
      // In-place compaction: same pattern as isAllowed().
      let write = 0;
      for (let i = 0; i < timestamps.length; i++) {
        if (timestamps[i] > cutoff) {
          timestamps[write++] = timestamps[i];
        }
      }
      timestamps.length = write;
      if (write === 0) {
        this.windows.delete(key);
      }
    }
  }

  /** Number of tracked keys (for testing/monitoring). */
  get size(): number {
    return this.windows.size;
  }

  /** Clear all tracked keys. For test isolation only — not for production use. */
  reset(): void {
    this.windows.clear();
  }
}

/**
 * Start a periodic prune interval for a SlidingWindowCounter and mark the
 * timer as unref'd so it never blocks process exit. Used for every
 * module-level SlidingWindowCounter singleton in this file and in sibling
 * per-route modules (e.g., app/api/analytics/track/throttle.ts). The
 * single-instance-assumption caveat on invoiceEndpointThrottle below
 * applies equally to every caller.
 *
 * Returns the timer handle so callers can optionally hold a reference for
 * test-time clearInterval. Module singletons typically discard the return
 * value — the helper's internal `unref()` is what keeps the timer from
 * blocking exit.
 */
export function startPruneInterval(
  counter: SlidingWindowCounter,
  ms = 60_000,
): NodeJS.Timeout {
  const handle = setInterval(() => counter.prune(), ms);
  handle.unref();
  return handle;
}

// ---------------------------------------------------------------------------
// PendingConnectionTracker — tracks unauthenticated sockets per IP
// ---------------------------------------------------------------------------

export class PendingConnectionTracker {
  private counts: Map<string, number> = new Map();
  private maxPerIp: number;

  constructor(maxPerIp: number) {
    this.maxPerIp = maxPerIp;
  }

  /** Try to add a pending connection. Returns false if over limit. */
  add(ip: string): boolean {
    const current = this.counts.get(ip) ?? 0;
    if (current >= this.maxPerIp) {
      return false;
    }
    this.counts.set(ip, current + 1);
    return true;
  }

  /** Remove a pending connection (authenticated or disconnected). */
  remove(ip: string): void {
    const current = this.counts.get(ip) ?? 0;
    if (current <= 1) {
      this.counts.delete(ip);
    } else {
      this.counts.set(ip, current - 1);
    }
  }

  /** Current pending count for an IP (for testing/monitoring). */
  get(ip: string): number {
    return this.counts.get(ip) ?? 0;
  }
}

// ---------------------------------------------------------------------------
// IP extraction — Cloudflare-aware
// ---------------------------------------------------------------------------

/**
 * Extract the client IP from a raw Node `IncomingMessage` (the WS upgrade
 * path; see `server/ws-handler.ts` for the caller). When `cf-connecting-ip`
 * is absent we fall back to `socket.remoteAddress`, which cannot be spoofed
 * at the TCP level.
 *
 * This deliberately diverges from `extractClientIpFromHeaders` (which has
 * no socket access and collapses missing `cf-connecting-ip` to `"unknown"`).
 * The asymmetry is intentional — see that function's docblock below.
 */
export function extractClientIp(req: IncomingMessage): string {
  // Trust cf-connecting-ip (set by Cloudflare, not spoofable when traffic
  // flows through the proxy). This is the only reliable header in production.
  const cfIp = req.headers["cf-connecting-ip"];
  if (typeof cfIp === "string" && cfIp) {
    return cfIp;
  }

  // Do NOT trust x-forwarded-for — absence of cf-connecting-ip means traffic
  // bypassed Cloudflare. An attacker with the origin IP could spoof XFF to
  // rotate IPs and bypass all per-IP rate limiting. Fall through to
  // remoteAddress which cannot be spoofed at the TCP level.
  const remoteAddress = req.socket.remoteAddress;
  if (!remoteAddress) {
    log.warn(
      { sec: true },
      "No client IP available — possible direct-to-origin connection",
    );
    return "unknown";
  }
  return remoteAddress;
}

// ---------------------------------------------------------------------------
// IP extraction — Next.js API routes (Web Request API)
// ---------------------------------------------------------------------------

/**
 * Extract the client IP from a Next.js App Router `Request.headers` object
 * (Web-API `Headers`). Used by `/api/analytics/track`, `/api/shared/[token]`,
 * and any other route handler that does per-IP rate limiting.
 *
 * When `cf-connecting-ip` is absent this returns `"unknown"` rather than
 * falling back to a socket IP. The Web-API Request has no access to the
 * underlying `socket.remoteAddress`. We deliberately do NOT consult
 * `x-forwarded-for` here either — it is spoofable in any non-Cloudflare
 * path and would silently share one bucket with a real direct-to-origin
 * IP. Collapsing to `"unknown"` fails closed.
 *
 * This is intentionally asymmetric with `extractClientIp` (the
 * `IncomingMessage` variant), which does have socket access and can fall
 * back safely.
 */
export function extractClientIpFromHeaders(headers: Headers): string {
  const cfIp = headers.get("cf-connecting-ip");
  if (cfIp) return cfIp;
  // In non-Cloudflare environments (dev, staging), use x-forwarded-for
  // which Next.js sets from the TCP connection. In production behind
  // Cloudflare, cf-connecting-ip is always present — XFF is only reached
  // if traffic bypasses Cloudflare (direct-to-origin), which is an
  // operational concern, not a spoofing vector at that point.
  const xff = headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return "unknown";
}

// ---------------------------------------------------------------------------
// HTTP rate limiter singleton for public share endpoints
// ---------------------------------------------------------------------------

export const shareEndpointThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: parseInt(process.env.SHARE_RATE_LIMIT_PER_MIN ?? "60", 10),
});

startPruneInterval(shareEndpointThrottle);

// ---------------------------------------------------------------------------
// HTTP rate limiter singleton for authenticated billing invoice endpoint
// ---------------------------------------------------------------------------
//
// Keyed by authenticated user.id (UUID). Defense-in-depth behind Cloudflare's
// IP-based rate limiting — user-ID keying prevents cross-user pollution on
// shared IPs (e.g., corporate NAT) and applies consistently in all envs.
//
// Single-instance assumption: in-memory counter is correct for the current
// Hetzner deployment (see apps/web-platform/infra/server.tf — no count/for_each).
// When the infra scales to >1 instance, switch to Redis-backed throttling.

export const invoiceEndpointThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: parseInt(process.env.INVOICE_RATE_LIMIT_PER_MIN ?? "10", 10),
});

startPruneInterval(invoiceEndpointThrottle);

/** Test-only helper: clear the invoice throttle state between tests. */
export function __resetInvoiceThrottleForTest(): void {
  invoiceEndpointThrottle.reset();
}

// ---------------------------------------------------------------------------
// Rate limit rejection logging + Sentry breadcrumbs
// ---------------------------------------------------------------------------

export function logRateLimitRejection(
  layer: string,
  key: string,
  extra: Record<string, unknown> = {},
): void {
  log.warn({ sec: true, layer, key, ...extra }, `Rate limited: ${layer}`);
  Sentry.addBreadcrumb({
    category: "rate-limit",
    message: `Layer ${layer} triggered for ${key}`,
    level: "warning",
  });
}

// ---------------------------------------------------------------------------
// Singleton instances (used by ws-handler)
// ---------------------------------------------------------------------------

export const connectionThrottle = new SlidingWindowCounter({
  windowMs: RATE_LIMIT_CONFIG.connectionWindowMs,
  maxRequests: RATE_LIMIT_CONFIG.connectionsPerWindow,
});

export const sessionThrottle = new SlidingWindowCounter({
  windowMs: RATE_LIMIT_CONFIG.sessionWindowMs,
  maxRequests: RATE_LIMIT_CONFIG.sessionsPerWindow,
});

export const pendingConnections = new PendingConnectionTracker(
  RATE_LIMIT_CONFIG.maxPendingPerIp,
);

// Periodic cleanup to prevent unbounded memory growth from stale entries.
// Lazy eviction in isAllowed() only cleans keys that are actively checked —
// IPs that connect once and never return accumulate until pruned.
startPruneInterval(connectionThrottle);

startPruneInterval(sessionThrottle, 300_000);
