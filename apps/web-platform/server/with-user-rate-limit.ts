import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import {
  SlidingWindowCounter,
  startPruneInterval,
} from "@/server/rate-limiter";
import { warnSilentFallback } from "@/server/observability";

// Per-user rate limit wrapper for authenticated GET handlers. Keyed by
// user.id (not IP) — authenticated callers have stable identity across
// NAT/VPN transitions; IP keys would both over-limit users on shared NAT
// and under-limit attackers rotating residential proxies.
//
// Over-quota events mirror to Sentry at warning level (not error). Rule
// `cq-silent-fallback-must-mirror-to-sentry` explicitly exempts rate-limit
// hits from the error-tier requirement — they are an expected degraded
// state, not an error, but still worth operator visibility.

type Handler = (req: Request) => Promise<Response>;

export interface WithUserRateLimitOptions {
  /** Per-user request budget per 60-second sliding window. */
  perMinute: number;
  /** Sentry feature tag, e.g. "kb-chat.thread-info". Also the counter key scope. */
  feature: string;
}

export function withUserRateLimit(
  handler: Handler,
  opts: WithUserRateLimitOptions,
): Handler {
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

    // Unauthenticated: defer to the inner handler. The inner is responsible
    // for its own 401; the wrapper does not consume a counter slot or
    // fabricate an auth response.
    if (!user) return handler(req);

    if (!counter.isAllowed(user.id)) {
      warnSilentFallback(null, {
        feature: opts.feature,
        op: "rate-limit",
        message: "Per-user rate limit tripped",
        extra: { userId: user.id },
      });
      return NextResponse.json(
        { error: "Too many requests" },
        { status: 429, headers: { "Retry-After": "60" } },
      );
    }

    return handler(req);
  };
}
