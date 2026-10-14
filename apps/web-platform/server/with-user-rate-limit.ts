import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { verifiedUserId, type VerifiedUser } from "@/server/request-auth";
import {
  SlidingWindowCounter,
  startPruneInterval,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import { hashUserIdValue } from "@/server/userid-pseudonymize";

// Per-user rate limit wrapper for authenticated GET handlers.
//
// Behavior:
//   - Resolves the caller id via `verifiedUserId(req)` — the middleware-
//     minted `x-soleur-auth-user-id` header on matcher-covered requests
//     (zero auth RTT), falling back to `auth.getUser()` when the header is
//     absent (fail-closed: never trusts an unverifiable value). The inner
//     handler receives `{ id }` only — all 12 consumers read only `user.id`
//     (verified 2026-09-25), so the auth payload narrows to exactly that.
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

type Handler = (req: Request, user: VerifiedUser) => Promise<Response>;

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
    const userId = await verifiedUserId(req);
    if (!userId) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    const user = { id: userId };

    // Sentry symmetric userId pseudonymisation — #3710 PR-B deliverable 1.
    //
    // Forks the current Sentry scope so `setUser({id: hashUserIdValue(user.id)})`
    // applies only to the inner handler's request lifecycle. The custom
    // `http.createServer` boot path in `server/index.ts:51` bypasses
    // `@sentry/nextjs`'s auto-installed per-request wrapper, so without this
    // explicit isolation a setUser from request A could leak into a Sentry
    // event captured during request B. ADR-029 (rename-at-boundary). F3 gate
    // verified by `test/sentry-scope-isolation.test.ts`.
    return Sentry.withIsolationScope(async () => {
      Sentry.getCurrentScope().setUser({ id: hashUserIdValue(user.id) });

      if (!counter.isAllowed(user.id)) {
        logRateLimitRejection(opts.feature, user.id);
        return NextResponse.json(
          { error: "Too many requests" },
          { status: 429, headers: { "Retry-After": "60" } },
        );
      }

      return handler(req, user);
    });
  };
}
