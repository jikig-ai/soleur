// Sliding-window throttle for /api/analytics/track. Sibling module per
// cq-nextjs-route-files-http-only-exports (route files may only export HTTP
// method handlers in Next.js 15 App Router).
import {
  SlidingWindowCounter,
  startPruneInterval,
} from "@/server/rate-limiter";

const RATE_PER_MIN = parseInt(
  process.env.ANALYTICS_TRACK_RATE_PER_MIN ?? "120",
  10,
);

// Single-instance in-memory counter (#2391): inherits the Redis-switch caveat
// documented in server/rate-limiter.ts near `invoiceEndpointThrottle`. When
// infra scales to >1 Node instance, all SlidingWindowCounter consumers
// (invoice, session, analytics-track) must switch to Redis together or the
// per-instance counts drift out of the shared quota.
export const analyticsTrackThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: RATE_PER_MIN,
});

// Periodic cleanup; see startPruneInterval docblock.
startPruneInterval(analyticsTrackThrottle);

/** Test-only helper: clear the in-memory throttle between tests. */
export function __resetAnalyticsTrackThrottleForTest(): void {
  analyticsTrackThrottle.reset();
}
