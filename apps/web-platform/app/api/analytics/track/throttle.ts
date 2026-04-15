// Sliding-window throttle for the /api/analytics/track route.
//
// Lives in a sibling module (not the route file) because Next.js 15's
// App Router rejects any non-HTTP-method export from a route file with
// "Type error: Route ... does not match the required types of a Next.js
// Route." See review fix for PR #2347 post-merge Docker build failure.
import { SlidingWindowCounter } from "@/server/rate-limiter";

const RATE_PER_MIN = parseInt(
  process.env.ANALYTICS_TRACK_RATE_PER_MIN ?? "120",
  10,
);

export const analyticsTrackThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: RATE_PER_MIN,
});

/** Test-only helper: clear the in-memory throttle between tests. */
export function __resetAnalyticsTrackThrottleForTest(): void {
  analyticsTrackThrottle.reset();
}
