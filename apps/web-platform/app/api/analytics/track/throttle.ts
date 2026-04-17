// Sliding-window throttle for /api/analytics/track. Sibling module per
// cq-nextjs-route-files-http-only-exports (route files may only export HTTP
// method handlers in Next.js 15 App Router).
import { SlidingWindowCounter } from "@/server/rate-limiter";

const RATE_PER_MIN = parseInt(
  process.env.ANALYTICS_TRACK_RATE_PER_MIN ?? "120",
  10,
);

export const analyticsTrackThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: RATE_PER_MIN,
});

// Periodic cleanup prevents unbounded memory growth from one-hit IPs that
// lazy eviction never re-checks. Matches shareEndpointThrottle /
// invoiceEndpointThrottle in server/rate-limiter.ts.
const pruneAnalyticsInterval = setInterval(
  () => analyticsTrackThrottle.prune(),
  60_000,
);
pruneAnalyticsInterval.unref();

/** Test-only helper: clear the in-memory throttle between tests. */
export function __resetAnalyticsTrackThrottleForTest(): void {
  analyticsTrackThrottle.reset();
}
