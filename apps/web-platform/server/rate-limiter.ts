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

    const timestamps = this.windows.get(key);
    const valid = timestamps ? timestamps.filter((t) => t > cutoff) : [];

    if (valid.length >= this.config.maxRequests) {
      this.windows.set(key, valid);
      return false;
    }

    valid.push(now);
    this.windows.set(key, valid);
    return true;
  }

  /** Remove keys with zero active entries. */
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

  /** Number of tracked keys (for testing/monitoring). */
  get size(): number {
    return this.windows.size;
  }
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

export function extractClientIp(req: IncomingMessage): string {
  const cfIp = req.headers["cf-connecting-ip"];
  if (typeof cfIp === "string" && cfIp) {
    return cfIp;
  }

  const xff = req.headers["x-forwarded-for"];
  if (typeof xff === "string" && xff) {
    const first = xff.split(",")[0]?.trim();
    if (first) return first;
  }

  return req.socket.remoteAddress ?? "unknown";
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
