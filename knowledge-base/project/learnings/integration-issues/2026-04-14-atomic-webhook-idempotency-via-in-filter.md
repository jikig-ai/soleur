---
module: Billing
date: 2026-04-14
problem_type: integration_issue
component: payments
symptoms:
  - "Replayed Stripe invoice.paid event could silently reactivate a cancelled subscription"
  - "Per-session WebSocket cache kept user in active state up to session end after webhook suspended account"
  - "Authenticated user could spam /api/billing/invoices (only Cloudflare IP throttle)"
  - "Past-due banner re-appeared after every page reload even after dismissal"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [stripe, webhook, idempotency, toctou, postgrest, in-filter, websocket, rate-limit]
---

# Atomic Webhook Idempotency via PostgREST `.in()` Filter

## Problem

PR #2186 resolved four deferred P3 items from the invoice-recovery billing work (PR #2081):

- **#2102** — Stripe webhook `invoice.paid` handler unconditionally set `subscription_status = 'active'` for any row matching `stripe_customer_id`. A replayed paid invoice on an already-cancelled subscription silently reactivated it.
- **#2103** — `past_due` banner dismiss was backed by React `useState` only, so every reload showed the banner again in the same tab.
- **#2104** — `ClientSession.subscriptionStatus` was cached at auth-time and never refreshed. A user suspended mid-session via Stripe webhook could keep chatting until reconnect (potentially hours).
- **#2105** — `/api/billing/invoices` only had Cloudflare IP throttling. An authenticated user scripting the endpoint from multiple IPs had no application-level brake.

All four shared the same billing surface and same review context, so they shipped in one PR.

## Solution

### 1. Atomic conditional UPDATE via `.in()` filter (the core insight)

Replace SELECT-then-UPDATE with a single atomic statement that encodes the precondition as a WHERE predicate:

```ts
// apps/web-platform/app/api/webhooks/stripe/route.ts (invoice.paid case)
const { data, error } = await supabase
  .from("users")
  .update({ subscription_status: "active" })
  .eq("stripe_customer_id", customerId)
  .in("subscription_status", ["past_due", "unpaid"])
  .select("id");

// matched === 0 is not an error — the guard short-circuits cancelled/active/etc.
logger.info(
  { customerId, matched: data?.length ?? 0, invoiceId: invoice.id },
  "Webhook: invoice.paid applied",
);
```

PostgREST (`@supabase/supabase-js@^2.49.0`, postgrest-js v2.58 per Context7) supports `.in()` on `.update()` targets. The emitted SQL is roughly `UPDATE users SET subscription_status='active' WHERE stripe_customer_id=$1 AND subscription_status = ANY($2)`. No rows match when the current status is `cancelled`, `active`, `incomplete`, or `none` — the update is a no-op at the DB level, not a race between SELECT and UPDATE.

`.select("id")` after the update returns the matched rows, enabling `matched: 0 | 1` observability on Better Stack/Sentry without changing the HTTP contract.

### 2. SSR-safe `sessionStorage` persistence for the banner

```tsx
const BANNER_DISMISS_KEY = "soleur:past_due_banner_dismissed";

function PaymentWarningBanner({ subscriptionStatus }: { subscriptionStatus: string | null }) {
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    try {
      if (sessionStorage.getItem(BANNER_DISMISS_KEY) === "1") setDismissed(true);
    } catch {
      // sessionStorage unavailable (private mode) — keep default false.
    }
  }, []);

  function dismiss() {
    setDismissed(true);
    try { sessionStorage.setItem(BANNER_DISMISS_KEY, "1"); } catch { /* ignore */ }
  }
  // ...
}
```

Initial render is deterministic (`dismissed=false` matches SSR), then the `useEffect` hydrates from `sessionStorage`. Avoids Next.js hydration mismatches. `sessionStorage` is tab-scoped, so a fresh tab re-shows the warning.

### 3. 60s WS refresh timer with post-await readyState guard

```ts
// apps/web-platform/server/ws-handler.ts
async function refreshSubscriptionStatus(userId: string, session: ClientSession) {
  try {
    const { data, error } = await supabase
      .from("users")
      .select("subscription_status")
      .eq("id", userId)
      .single();

    // MANDATORY guard per 2026-03-20 learning: socket may have closed during the await.
    if (session.ws.readyState !== WebSocket.OPEN) return;

    if (error || !data) return; // fail open — preserve cached value
    session.subscriptionStatus = data.subscription_status ?? undefined;
    if (data.subscription_status === "unpaid") {
      checkSubscriptionSuspended(userId, session);
    }
  } catch (err) {
    log.warn({ userId, err }, "Subscription status refresh failed — keeping cached value");
  }
}

function startSubscriptionRefresh(userId: string, session: ClientSession) {
  if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
  const timer = setInterval(
    () => void refreshSubscriptionStatus(userId, session),
    WS_SUBSCRIPTION_REFRESH_INTERVAL_MS,
  );
  timer.unref?.();
  session.subscriptionRefreshTimer = timer;
}
```

Closes the TOCTOU window from "indefinite until reconnect" to `<=60s`. `.unref()` so test processes and SIGTERM can exit cleanly. Timer cleared on every session teardown path.

### 4. User-ID keyed rate limit after auth

```ts
// apps/web-platform/server/rate-limiter.ts
export const invoiceEndpointThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: parseInt(process.env.INVOICE_RATE_LIMIT_PER_MIN ?? "10", 10),
});

// apps/web-platform/app/api/billing/invoices/route.ts
if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
if (!invoiceEndpointThrottle.isAllowed(user.id)) {
  logRateLimitRejection("invoice-endpoint", user.id);
  return NextResponse.json(
    { error: "Too many requests" },
    { status: 429, headers: { "Retry-After": "60" } },
  );
}
```

Order matters: auth first, then throttle. Unauthenticated requests return 401 without consuming a slot — prevents scraping from polluting the bucket and prevents cross-user collision on shared IPs (corporate NAT).

## Key Insight

**Atomic conditional UPDATE encodes the precondition as a WHERE predicate, eliminating the SELECT-then-UPDATE race at the DB level.** This is the webhook-idempotency equivalent of an optimistic lock — the common pattern "check current state, then write" has a TOCTOU window between the two queries that a concurrent write can exploit. For webhook replays specifically:

- `invoice.paid` → only restore from `past_due|unpaid`
- `customer.subscription.deleted` → only transition from `active|past_due|unpaid` (follow-up, tracked in #2190)
- Any handler that "restores" or "cancels" based on prior state

The pattern: one SQL statement, filters as guards, observability via `.select("id")` + `matched` log field.

## Why Not These Alternatives

| Alternative | Why not |
|-------------|---------|
| SELECT then UPDATE | Opens TOCTOU window; concurrent `.deleted` can flip row after the SELECT but before the UPDATE. |
| Drop the `invoice.paid` handler entirely | `customer.subscription.updated` covers `active` transitions, but the belt-and-suspenders restore was intentional. Keeping it + guarding it is cheaper than re-litigating. |
| Supabase Realtime / pub-sub for WS invalidation | Requires persistent realtime connection per WS worker. Periodic 60s refresh is a stopgap that eliminates 99% of the staleness window with zero infra change. |
| Middleware-based rate limit | Project pattern is local-per-route (share endpoint, WS). Keep consistency. |
| IP-based rate limit on invoice endpoint | Authenticated endpoint. User-ID keying is strictly better — avoids shared-IP collateral. |

## Cross-References

- Related (async-boundary TOCTOU pattern): [`2026-03-20-websocket-first-message-auth-toctou-race.md`](../2026-03-20-websocket-first-message-auth-toctou-race.md) — the exact `ws.readyState !== WebSocket.OPEN` guard pattern applied here.
- Related (TOCTOU fix template): [`2026-03-18-stop-hook-toctou-race-fix.md`](../2026-03-18-stop-hook-toctou-race-fix.md) — bash filesystem variant; this learning is the Supabase/webhook variant.
- Related (Stripe status enum): [`2026-04-13-stripe-status-mapping-check-constraint.md`](../2026-04-13-stripe-status-mapping-check-constraint.md) — the `users.subscription_status` CHECK constraint enum the `.in()` filter respects.
- Related (batching multiple billing fixes into one PR): [`2026-04-13-billing-review-findings-batch-fix.md`](../2026-04-13-billing-review-findings-batch-fix.md) — project-approved pattern.
- PR: #2186
- Closes: #2102, #2103, #2104, #2105 (4 fixes), #2192 (observability enhancement)
- Follow-up issues: #2188 (missing stripe_customer_id unique index), #2189 (mapStripeStatus exhaustive), #2190 (.deleted guard), #2191 (clearSessionTimers + jitter + consecutive-failure close), #2193-2197 (UI/test/infra polish)

## Review Findings Surfaced

Nine parallel review agents (git-history, pattern, architecture, security, performance, data-integrity, agent-native, code-quality, test-design) surfaced 10 follow-up issues — zero P1 merge blockers, but two reviewers independently flagged the pre-existing missing `users.stripe_customer_id` index as the next priority (every Stripe webhook UPDATE currently does a seq scan). Filed as #2188.

## Session Errors

Session errors: none detected. The implementation phase spawned 4 parallel TDD subagents that each returned GREEN without rework. The only mid-session ripple was updating the webhook test's `mockIn.mockResolvedValue(...)` pattern to `mockSelect.mockResolvedValue(...)` after adding `.select("id")` to the route — caught immediately by running the file-scoped test suite before committing. No hard-rule violation, no workflow deviation.

**Prevention:** when extending a mocked fluent builder chain with a new leaf method, configure the mock through the new leaf rather than intermediate links. Already implicit in "run full test suite after each change" — no new rule needed.

## Tags

category: integration-issues
module: billing
