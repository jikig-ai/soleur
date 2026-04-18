import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import {
  SlidingWindowCounter,
  startPruneInterval,
  logRateLimitRejection,
} from "@/server/rate-limiter";

// Per-user rate limit wrapper for authenticated GET handlers.
//
// Behavior:
//   - Calls `supabase.auth.getUser()` ONCE per request and passes the
//     authenticated `user` to the inner handler, so wrapped routes must
//     not call `getUser()` again.
//   - Returns 401 at the wrapper for unauthenticated callers — the
//     inner handler never sees a null user, so an unauth flood cannot
//     bypass the limiter or force duplicate auth round-trips.
//   - Keys the counter on `user.id`. IP keys would both over-limit users
//     on shared NAT and under-limit attackers on rotating residential
//     proxies; `user.id` is stable per account.
//   - Over-quota events emit a Sentry breadcrumb via the existing
//     `logRateLimitRejection` helper (matches the invoice/shared/analytics
//     throttle precedent in rate-limiter.ts). Rate-limit hits are an
//     exempt expected state per rule `cq-silent-fallback-must-mirror-to-
//     sentry` — breadcrumb-tier preserves operator visibility without
//     generating standalone Sentry events.
//
// Single-instance assumption inherited from `rate-limiter.ts`
// (`invoiceEndpointThrottle` note). In-memory counter is correct for the
// current Hetzner single-node deployment; migrate to Redis when infra
// scales beyond one replica.
//
// This factory MUST be called at module scope. Each call allocates a
// SlidingWindowCounter + prune interval; invoking per-request would leak
// both.

type Handler = (req: Request, user: User) => Promise<Response>;

export interface WithUserRateLimitOptions {
  /** Per-user request budget per 60-second sliding window. */
  perMinute: number;
  /**
   * Sentry feature tag and rate-limit-layer label, e.g. "kb-chat.thread-info".
   * Used by `logRateLimitRejection` for breadcrumb dashboards.
   */
  feature: string;
}

export function withUserRateLimit(
  handler: Handler,
  opts: WithUserRateLimitOptions,
): (req: Request) => Promise<Response> {
  const counter = new SlidingWindowCounter({
    windowMs: 60_000,
    maxRequests: opts.perMinute,
  });
  startPruneInterval(counter);

  return async function rateLimited(req: Request): Promise<Response> {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    if (!counter.isAllowed(user.id)) {
      logRateLimitRejection(opts.feature, user.id);
      return NextResponse.json(
        { error: "Too many requests" },
        { status: 429, headers: { "Retry-After": "60" } },
      );
    }

    return handler(req, user);
  };
}
