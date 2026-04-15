# fix(billing): harden webhooks, WS cache, and invoice endpoint

**Date:** 2026-04-14
**Branch:** `feat-fix-billing-hardening`
**Worktree:** `.worktrees/feat-fix-billing-hardening`
**Closes:** #2102, #2103, #2104, #2105
**Source:** Deferred P3 items from code review of PR #2081 (tracked in review issue #2099)

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** 4 fixes + risks + testing
**Research sources:** Context7 (`/supabase/postgrest-js` v2.58), WebSearch (Stripe webhook idempotency, Next.js 15 SSR/sessionStorage, in-memory rate limiting, Node.js setInterval leaks), project learnings (9 relevant WS/TOCTOU/webhook entries), infra inspection.

### Key Improvements

1. **Verified `.in()` on `.update()`** — Context7 confirms PostgREST supports `.update().in()` chaining (see [Modify Records with update()](#21-verified-postgrest-update-with-in-filter-context7)). No fallback needed.
2. **Deployment topology confirms in-memory rate limit is correct** — `infra/server.tf` provisions a single `hcloud_server` without `count`/`for_each`. In-memory `SlidingWindowCounter` is the right tool for current scale; noted Redis migration trigger for future horizontal scale.
3. **TOCTOU async-boundary pattern** — `2026-03-20-websocket-first-message-auth-toctou-race.md` documents the exact anti-pattern in our codebase. The refresh timer design must include a `ws.readyState !== WebSocket.OPEN` guard after the async DB query and before mutating session state.
4. **Idempotency discovered as cross-cutting concern** — Stripe explicitly recommends storing processed `event.id`s as a second line of defense against retries. Scoped out of this PR (larger change) but recorded for follow-up tracking.
5. **Graceful shutdown integration** — `2026-04-05-graceful-sigterm-shutdown-node-patterns.md` establishes that WebSocket cleanup must iterate `wss.clients`. The new `subscriptionRefreshTimer` must be cleared in the same shutdown path.

### New Considerations Discovered

- Per the 2026-02-12 learning on review-compound-before-commit, run `skill: soleur:compound` before the final commit.
- Test framework caveat from `2026-03-27-ws-session-race-abort-before-replace.md`: `vi.mock()` hoisting is vitest-only; if tests ever run under bun, prefer dynamic imports with env set beforehand. Current project only uses vitest, so `vi.useFakeTimers()` and `vi.mock()` are safe — documented for future-proofing.
- Sentry breadcrumb pattern from existing `logRateLimitRejection` auto-integrates with the new invoice throttle — no extra work.

## Summary

Resolve four deferred P3 items from the invoice-recovery billing work (PR #2081):

1. **#2102** — Guard `invoice.paid` webhook to only restore `subscription_status = 'active'` when the current status is `past_due` or `unpaid`. Prevents silent reactivation of cancelled subscriptions if Stripe replays a paid invoice.
2. **#2103** — Persist the past-due warning banner dismiss in `sessionStorage` so a page refresh does not re-show the banner within the same tab session, while a new tab still surfaces the warning.
3. **#2104** — Shrink the TOCTOU window in the WebSocket `ClientSession.subscriptionStatus` cache by adding a lightweight periodic refresh of the cached status for active long-lived connections.
4. **#2105** — Add application-level per-user rate limiting to `GET /api/billing/invoices` as defense-in-depth behind Cloudflare.

All four ship in a single PR because they share the same billing surface area, same review context (PR #2081 / issue #2099), and each fix is small and well-contained. Grouping keeps review overhead low and avoids branch churn.

## Out of Scope

- Chat/WS streaming cleanup (separate PR, follow-up)
- KB routes refactor (separate PR, follow-up)
- Leader/Dashboard polish (separate PR, follow-up)
- Stripe webhook → WS realtime invalidation channel (larger architectural change — `#2104` resolution uses periodic refresh instead; a Realtime-driven invalidation is a future enhancement if metered usage becomes a requirement)
- Migration changes (no DB schema changes required)

## Files to Touch

| File | Change |
|------|--------|
| `apps/web-platform/app/api/webhooks/stripe/route.ts` | Guard `invoice.paid` handler (#2102) |
| `apps/web-platform/app/(dashboard)/layout.tsx` | Replace `bannerDismissed` state with sessionStorage-backed helper (#2103) |
| `apps/web-platform/server/ws-handler.ts` | Add periodic `refreshSubscriptionStatus` timer on `ClientSession` (#2104) |
| `apps/web-platform/server/rate-limiter.ts` | Add `invoiceEndpointThrottle` singleton (#2105) |
| `apps/web-platform/app/api/billing/invoices/route.ts` | Wire application-level rate limit using authenticated user ID (#2105) |
| `apps/web-platform/test/stripe-webhook-invoice.test.ts` | Add test cases for invoice.paid guard (#2102) |
| `apps/web-platform/test/webhook-subscription.test.ts` | (if needed) regression test interaction with cache (#2104) |
| `apps/web-platform/test/billing-section.test.tsx` OR new `dashboard-layout.test.tsx` | Test sessionStorage dismiss behavior (#2103) |
| `apps/web-platform/test/ws-handler.test.ts` (new, scoped) OR extend existing | Test periodic refresh timer (#2104) |
| `apps/web-platform/test/api-billing-invoices-ratelimit.test.ts` (new) | Test 429 on invoice endpoint abuse (#2105) |

## Implementation

### 1. #2102 — Guard `invoice.paid` handler

**Current (route.ts:138-163):** unconditionally sets `subscription_status = 'active'` on any user whose `stripe_customer_id` matches. This means a replayed `invoice.paid` event for an already-cancelled customer would silently flip their status back to `active`.

**Fix:** Scope the update to rows where the current status is `past_due` or `unpaid` by adding an `.in("subscription_status", ["past_due", "unpaid"])` filter to the update chain. Supabase/PostgREST supports `.in()` on update targets — the update is a no-op when no rows match, which is the desired behavior for `active`, `cancelled`, `incomplete`, and other states.

```ts
// apps/web-platform/app/api/webhooks/stripe/route.ts
case "invoice.paid": {
  const invoice = event.data.object as Stripe.Invoice;
  const customerId =
    typeof invoice.customer === "string"
      ? invoice.customer
      : invoice.customer?.id;

  if (customerId) {
    // Only restore active if currently past_due or unpaid.
    // customer.subscription.updated is the source of truth for active transitions;
    // this is a belt-and-suspenders restore that must not reactivate cancelled subs.
    const { error } = await supabase
      .from("users")
      .update({ subscription_status: "active" })
      .eq("stripe_customer_id", customerId)
      .in("subscription_status", ["past_due", "unpaid"]);

    if (error) {
      logger.error(
        { error, customerId },
        "Webhook: failed to update user on invoice.paid",
      );
      return NextResponse.json(
        { error: "DB update failed" },
        { status: 500 },
      );
    }
  }
  break;
}
```

**Verification note:** PostgREST `.in()` on `.update()` is supported and translates to `WHERE status IN (...)` on the UPDATE statement. Project pins `@supabase/supabase-js@^2.49.0`; postgrest-js v2.58 docs on Context7 explicitly show this exact pattern.

#### 2.1 Verified: PostgREST update with .in() filter (Context7)

Context7 (`/supabase/postgrest-js`, v2.58) confirms the exact pattern:

```typescript
const { data, error } = await postgrest
  .from('users')
  .update({ status: 'OFFLINE' })
  .in('username', ['user1', 'user2', 'user3'])
  .select()
```

And explicitly: _"General Filters can be used before and after invoking .update(). It is required to use at least one of these filters when using .update()."_ Our chain `.update(...).eq(customer_id, ...).in(status, [past_due, unpaid])` combines two filters — both apply to the WHERE clause on the UPDATE. No fallback SQL function needed.

#### 2.2 Research Insight: Stripe webhook idempotency (WebSearch)

Stripe's own docs recommend two complementary defenses that this fix partially implements:

1. **State-aware guards** — "Always query your database for the current subscription state before applying payment-related state changes from webhook events, ensuring you never inadvertently reactivate a deliberately cancelled subscription through duplicate or out-of-order event processing." (sources: [Stripe Webhooks Guide](https://www.magicbell.com/blog/stripe-webhooks-guide), [Using webhooks with subscriptions](https://docs.stripe.com/billing/subscriptions/webhooks)) — **✅ this PR implements this.**
2. **`event.id` deduplication** — Store processed event IDs and short-circuit replays. (source: [Handling Payment Webhooks Reliably](https://medium.com/@sohail_saifii/handling-payment-webhooks-reliably-idempotency-retries-validation-69b762720bf5)) — **Out of scope; larger change (requires a `stripe_webhook_events` table or cache). Track as a follow-up.**

**Action:** After this PR merges, file a tracking issue for Stripe webhook `event.id` deduplication with rationale pulled from the Stripe docs. Milestone: Post-MVP / Later.

#### 2.3 Anti-pattern avoided: check-then-update across async boundary

An alternative design is SELECT-then-UPDATE:

```ts
// ANTI-PATTERN — DO NOT USE
const { data } = await supabase.from("users").select("subscription_status").eq("stripe_customer_id", customerId).single();
if (data?.subscription_status === "past_due" || data?.subscription_status === "unpaid") {
  await supabase.from("users").update({ subscription_status: "active" }).eq("stripe_customer_id", customerId);
}
```

This opens a TOCTOU window: between the SELECT and the UPDATE, a concurrent `customer.subscription.deleted` could flip the user to `cancelled`, and this handler would then overwrite it with `active`. The same anti-pattern is documented in `knowledge-base/project/learnings/2026-03-18-stop-hook-toctou-race-fix.md` (bash file-system variant) and `2026-03-20-websocket-first-message-auth-toctou-race.md` (WS async-with-state-mutation variant). Atomic `UPDATE ... WHERE status IN (...)` closes the window at the DB level.

#### 2.4 Edge cases surfaced by research

- **Out-of-order webhook delivery** — Stripe explicitly states "You might receive customer.subscription.deleted before customer.subscription.updated" ([Stripe docs](https://docs.stripe.com/billing/subscriptions/webhooks)). The `.in()` filter handles this correctly: a late `invoice.paid` after a processed `customer.subscription.deleted` finds `cancelled` status and no-ops.
- **Null `subscription_status`** — Trial users or newly-signed-up rows may have `NULL`. The `.in()` filter excludes NULLs (SQL `IN` is NULL-safe in a reject-NULL way), so no special handling needed.
- **Multiple users per customer** — A single Stripe customer is always one user in our schema (`stripe_customer_id` is unique per migration 021). The `.eq()` filter matches at most one row.

**Test additions** (`test/stripe-webhook-invoice.test.ts`):

- `invoice.paid` with current status `past_due` → updates to `active` ✅
- `invoice.paid` with current status `unpaid` → updates to `active` ✅
- `invoice.paid` with current status `active` → no-op (update matches 0 rows; no error) ✅
- `invoice.paid` with current status `cancelled` → no-op (critical — this is the bug being fixed) ✅
- `invoice.paid` with customerId missing → break without DB call (existing behavior preserved) ✅
- DB error path returns 500 (existing) ✅

### 2. #2103 — sessionStorage banner dismiss

**Current (`layout.tsx`:30, 227-251):** `bannerDismissed` is `useState(false)`. On every mount (reload, tab nav) it resets to `false` and the banner reappears, even if the user just dismissed it.

**Fix:** Back the dismiss state with `sessionStorage` so it persists within the tab session (cleared when the tab closes). Gate `window.sessionStorage` access in a `useEffect` (SSR-safe) with a defensive try/catch (private browsing in some browsers throws on `sessionStorage` writes).

```tsx
// apps/web-platform/app/(dashboard)/layout.tsx
const BANNER_DISMISS_KEY = "soleur:past_due_banner_dismissed";

const [bannerDismissed, setBannerDismissed] = useState(false);

// Hydrate dismiss state from sessionStorage (client-only).
useEffect(() => {
  try {
    if (sessionStorage.getItem(BANNER_DISMISS_KEY) === "1") {
      setBannerDismissed(true);
    }
  } catch {
    // sessionStorage unavailable (private mode) — keep default false.
  }
}, []);

function dismissBanner() {
  setBannerDismissed(true);
  try {
    sessionStorage.setItem(BANNER_DISMISS_KEY, "1");
  } catch {
    // ignore; dismiss still works for this render, just not across reloads
  }
}

// In JSX:
<button
  onClick={dismissBanner}
  aria-label="Dismiss payment warning"
  className="rounded p-1 text-neutral-400 hover:text-neutral-200"
>
  <XIcon className="h-4 w-4" />
</button>
```

**Edge cases:**

- Dismiss then reload same tab → banner stays dismissed. ✅
- Dismiss, close tab, reopen in new tab → banner re-appears. ✅ (sessionStorage is tab-scoped)
- Subscription recovers (status goes `past_due → active`) → the banner is already hidden by the `subscriptionStatus === "past_due"` guard. No need to clear the key — when the user next has a `past_due` event they get a fresh decision per-tab.
- SSR: `useEffect` gate means no hydration mismatch; initial render always shows `bannerDismissed=false` matching the server.

#### 3.1 Research Insight: SSR-safe sessionStorage pattern (WebSearch)

Next.js 15 App Router explicitly validates the pattern used here: _"During React hydration, useEffect is called, which means browser APIs like window are available to use without hydration mismatches. This is the primary solution for accessing sessionStorage and other browser APIs."_ (source: [Next.js react-hydration-error](https://nextjs.org/docs/messages/react-hydration-error))

The specific anti-pattern to avoid: _"Accessing window, document, localStorage, or navigator in the render path is a classic mismatch trigger. On the server those don't exist, so code branches will differ and the HTML will diverge."_ (source: [Fix Next.js 15 Hydration Errors](https://markaicode.com/nextjs-15-hydration-errors-fix/))

Our implementation is compliant:

- Initial render: `bannerDismissed = false` (deterministic; matches server).
- `useEffect` reads sessionStorage post-hydration and may flip it to `true` on a second render — React's reconciler handles this without warning because it is a client-only update, not a hydration comparison.

#### 3.2 Alternative rejected: `suppressHydrationWarning`

The search results document `suppressHydrationWarning={true}` as a valid option but explicitly discourage it: _"silencing the warning doesn't fix the problem."_ Our useEffect pattern actually solves the underlying SSR mismatch instead of suppressing it.

#### 3.3 Edge case surfaced by research

**Safari private browsing** — Historically threw on `sessionStorage.setItem`. Modern Safari (14+) allows sessionStorage in private mode, but the try/catch in our design is defense-in-depth for older browsers and for runtime quota exceptions. The test `sessionStorage.setItem throws → banner still hides` is specifically for this case.

**Test additions** (extend `billing-section.test.tsx` or add a small `dashboard-layout-banner.test.tsx`):

- Renders banner when `past_due` and no sessionStorage key → visible.
- Renders no banner when `past_due` and sessionStorage key set → hidden.
- Click dismiss → sets sessionStorage key AND hides banner.
- `sessionStorage.setItem` throws → banner still hides (in-memory state).

### 3. #2104 — Shrink TOCTOU window in WS subscription cache

**Current (`ws-handler.ts`:52-65, 601-635):** `subscriptionStatus` is cached at auth-time into the session and never updated. The docstring says "refreshed by billing check timer" but no such timer exists. A user who is suspended via Stripe webhook after auth can keep chatting until they reconnect (potentially hours during a long session).

**Fix:** Add a lightweight periodic refresh timer per authenticated session. The check is cheap (a single indexed select on `users.id`) and bounded by active session count, which is already capped by rate limits. Default refresh interval: 60 seconds (configurable via `WS_SUBSCRIPTION_REFRESH_INTERVAL_MS`). On refresh, if the status is now `unpaid`, trigger the existing `checkSubscriptionSuspended` path (send error frame + close). Clear the timer on disconnect.

```ts
// apps/web-platform/server/ws-handler.ts

// Config (near WS_IDLE_TIMEOUT_MS)
const WS_SUBSCRIPTION_REFRESH_INTERVAL_MS = parseInt(
  process.env.WS_SUBSCRIPTION_REFRESH_INTERVAL_MS ?? "60000",
  10,
);

// Extend ClientSession interface
export interface ClientSession {
  // ...existing fields...
  subscriptionStatus?: string;
  subscriptionRefreshTimer?: ReturnType<typeof setInterval>;
}

// New helper
async function refreshSubscriptionStatus(
  userId: string,
  session: ClientSession,
): Promise<void> {
  try {
    const { data, error } = await supabase
      .from("users")
      .select("subscription_status")
      .eq("id", userId)
      .single();
    if (error || !data) return; // fail open — keep prior cached value
    session.subscriptionStatus = data.subscription_status ?? undefined;
    if (data.subscription_status === "unpaid") {
      // Trigger the existing enforcement path.
      // Returns true if it closed the connection; either way, session is cleaned up.
      checkSubscriptionSuspended(userId, session);
    }
  } catch (err) {
    log.warn({ userId, err }, "Subscription status refresh failed — keeping cached value");
  }
}

function startSubscriptionRefresh(userId: string, session: ClientSession): void {
  if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
  const timer = setInterval(
    () => void refreshSubscriptionStatus(userId, session),
    WS_SUBSCRIPTION_REFRESH_INTERVAL_MS,
  );
  timer.unref?.(); // don't block process exit in tests
  session.subscriptionRefreshTimer = timer;
}

// At auth (after `sessions.set(userId, newSession)`):
startSubscriptionRefresh(userId, newSession);

// On disconnect / session teardown (wherever idleTimer is cleared):
if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
```

**Design notes:**

- 60s is a reasonable balance: median DB cost is ~5-15ms per session per minute; at 1000 concurrent sessions = ~150-300ms/s aggregate, negligible compared to chat message throughput.
- Failure modes: transient DB errors keep the cached value (fail-open matches middleware behavior). A permanent DB failure means a suspended user can keep chatting until reconnect — same as current behavior, no regression.
- Not using Supabase Realtime/Postgres LISTEN here because (a) our WS server is a separate process that would need a persistent Supabase realtime connection per worker, and (b) the webhook → DB → refresh path is already within a 60s window which is far better than the current "indefinite" window. A realtime invalidation channel is a future enhancement.
- Timer is `.unref()`'d so vitest doesn't hang the process.

#### 4.1 Critical: Async-boundary guard (per `2026-03-20-websocket-first-message-auth-toctou-race.md`)

The refresh timer has the same shape as the auth flow's TOCTOU bug: `await` a DB query, then mutate session state. The learning is explicit: _"Any time an async operation (network call, database query, file I/O) sits between a timer-based deadline and a state mutation, you have a TOCTOU window."_

Update `refreshSubscriptionStatus` to guard socket state after the await, before mutating `session.subscriptionStatus` or calling `checkSubscriptionSuspended`:

```ts
async function refreshSubscriptionStatus(
  userId: string,
  session: ClientSession,
): Promise<void> {
  try {
    const { data, error } = await supabase
      .from("users")
      .select("subscription_status")
      .eq("id", userId)
      .single();

    // Guard: socket may have closed (disconnect, idle timeout, suspension)
    // during the await. Do not mutate session state on a dead socket.
    if (session.ws.readyState !== WebSocket.OPEN) return;

    if (error || !data) return; // fail open — keep prior cached value
    session.subscriptionStatus = data.subscription_status ?? undefined;
    if (data.subscription_status === "unpaid") {
      checkSubscriptionSuspended(userId, session);
    }
  } catch (err) {
    log.warn({ userId, err }, "Subscription status refresh failed — keeping cached value");
  }
}
```

This guard is mandatory — without it the timer can run DB queries for users who already disconnected, leaking connections to Supabase and potentially calling `checkSubscriptionSuspended` on a CLOSING socket.

#### 4.2 Research Insight: setInterval memory leak prevention (WebSearch)

_"setInterval without clearInterval is a reference that prevents garbage collection of everything in its closure"_ (source: [Debugging Memory Leaks in React + Next.js](https://www.codewithseb.com/blog/debugging-memory-leaks-react-nextjs-guide)). The closure here captures `userId` (string, small) and `session` (the full object) — if we leak the interval, we leak the session and its WebSocket.

**Mitigation layers:**

1. **Timer stored on session** — `session.subscriptionRefreshTimer = timer` gives every cleanup path a handle.
2. **Cleared on every teardown path** — normal close, idle timeout (`WS_IDLE_TIMEOUT_MS`), disconnect grace expiry, subscription suspension close. Grep `ws-handler.ts` for `clearTimeout(session.idleTimer)` and add `clearInterval(session.subscriptionRefreshTimer)` adjacent to each.
3. **Graceful SIGTERM** — `2026-04-05-graceful-sigterm-shutdown-node-patterns.md` establishes iteration over `wss.clients` on SIGTERM. Ensure that iteration also clears per-session timers if present (belt-and-suspenders; `.unref()` already allows process exit, but explicit clear avoids a race during the 8s drain window).
4. **`.unref()` on the interval** — prevents hung test processes and hung graceful shutdown.

#### 4.3 Anti-pattern avoided: checking on every message

An earlier review explicitly rejected this; re-documented here because it is the most tempting "simpler" alternative. The `2026-04-13-ws-session-cache-subscription-status.md` learning spells out: _"Querying [subscription_status] on every message is wasteful. The worst case with caching is a brief window where a newly-suspended user can send a few more messages before reconnecting."_ The periodic-refresh design preserves the caching benefit (no per-message DB call) while shrinking the "brief window" from "indefinite" to "≤60s."

#### 4.4 Edge cases surfaced by research

- **Clock drift / suspended laptop** — `setInterval` in Node.js is event-loop-based, not wall-clock. A sleeping process stops ticking the timer. On wake, the next tick fires immediately then resumes the 60s cadence. Acceptable behavior for our case.
- **Supabase transient outage** — `refreshSubscriptionStatus` fails open (logs + preserves cached value). If the DB is down for 5 minutes, users stay on their cached status. This is symmetric with middleware's fail-open on the T&C query.
- **User row deleted** — `.single()` returns `PGRST116` error. Our error branch returns without mutating state, preserving the cached status. A separate process deleting a user mid-session is an ops scenario, not a security one — acceptable.

**Test additions** (extend `test/webhook-subscription.test.ts` or add a focused test):

- Mock DB returns `unpaid` on refresh → verify `close` called with `SUBSCRIPTION_SUSPENDED`.
- Mock DB returns same status → no action, no close.
- Mock DB throws → cached value preserved (no close).
- Timer is cleared on session teardown (assert `clearInterval` called).

### 4. #2105 — Per-user rate limit on invoice endpoint

**Current (`app/api/billing/invoices/route.ts`):** only Cloudflare rate limiting (IP-based, generic). No defense if an authenticated user scripts the endpoint from multiple IPs, and no consistent behavior across environments (dev has no Cloudflare).

**Fix:** Reuse the existing `SlidingWindowCounter` from `server/rate-limiter.ts`. Add an `invoiceEndpointThrottle` singleton keyed by authenticated `user.id` (not IP — we already have the user in hand after auth, and user-ID keying prevents cross-user pollution on shared IPs like corporate NAT). Default: 10 req/min per user (Stripe invoices list has no need for higher frequency given 5-min `Cache-Control`).

```ts
// apps/web-platform/server/rate-limiter.ts (append)
export const invoiceEndpointThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: parseInt(process.env.INVOICE_RATE_LIMIT_PER_MIN ?? "10", 10),
});

const pruneInvoiceInterval = setInterval(
  () => invoiceEndpointThrottle.prune(),
  60_000,
);
pruneInvoiceInterval.unref();
```

```ts
// apps/web-platform/app/api/billing/invoices/route.ts
import {
  invoiceEndpointThrottle,
  logRateLimitRejection,
} from "@/server/rate-limiter";

export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Per-user rate limit — defense-in-depth behind Cloudflare.
  if (!invoiceEndpointThrottle.isAllowed(user.id)) {
    logRateLimitRejection("invoice-endpoint", user.id);
    return NextResponse.json(
      { error: "Too many requests" },
      { status: 429, headers: { "Retry-After": "60" } },
    );
  }

  // ...existing Stripe fetch + response...
}
```

**Design notes:**

- Keyed by `user.id` (UUID) — not spoofable because we use Supabase's authenticated session.
- Order matters: auth first, then rate limit. An unauthenticated request returns 401 and never touches the throttle (prevents throttle pollution from scraping).
- Limit of 10/min matches conservative expected UX (user reloads the billing page; invoices load once with 5-min browser cache). Env override keeps ops flexibility.
- Not placed in middleware because the endpoint is a single GET and middleware doesn't currently handle rate-limit concerns — keep logic local per the share-endpoint pattern (`app/api/shared/[token]/route.ts`).

#### 5.1 Deployment topology validates in-memory rate limiter (infra inspection)

`apps/web-platform/infra/server.tf` provisions `resource "hcloud_server" "web"` **without `count` or `for_each`** — this is a single-instance deployment. In-memory `SlidingWindowCounter` is correct for current scale and matches the existing patterns (`shareEndpointThrottle`, `connectionThrottle`, `sessionThrottle`).

Search results flag the scaling caveat explicitly: _"In-memory rate limiting approaches in Next.js won't scale for larger production deployments with multiple servers, and switching to solutions like Redis is recommended"_ (sources: [How to Build an In-Memory Rate Limiter in Next.js](https://www.freecodecamp.org/news/how-to-build-an-in-memory-rate-limiter-in-nextjs/), [Rate Limiting Next.js API Routes using Upstash Redis](https://upstash.com/blog/nextjs-ratelimiting)). The moment we add a second `hcloud_server` (or Fly/Render scale-out), every in-memory throttle becomes under-enforced by the instance count.

**Action:** Add a comment to the new `invoiceEndpointThrottle` singleton noting the single-instance assumption, matching the pattern of other throttles in `rate-limiter.ts`. When the infra migrates to >1 instance, a tracking issue for Redis-backed throttles should exist. **Out of scope for this PR** but record as a follow-up if not already tracked.

#### 5.2 Research Insight: Auth-then-rate-limit ordering (WebSearch + codebase)

The share endpoint inverts this order (rate-limit first, then auth) because it is a public endpoint keyed by IP — unauthenticated requests must still be throttled to prevent scraping. For the invoice endpoint, the opposite is correct: auth first (user.id is the only sensible throttle key), then throttle. This prevents:

- **Throttle pollution from scraping** — unauthenticated requests returning 401 don't consume a slot; otherwise a single `user_id=null` bucket would collect global unauth traffic.
- **Incorrect key selection** — can't rate-limit by user ID until the user is identified.

This asymmetry is intentional; future route additions should pick the correct pattern based on auth semantics, not copy-paste.

#### 5.3 Edge cases surfaced by research

- **Retry-After header formatting** — RFC 7231 allows either seconds or an HTTP-date. `Retry-After: 60` is seconds (simpler, and what clients expect from rate-limit responses). Consistent with the share-endpoint pattern, though the share endpoint omits the header entirely. Worth adding here since this is the first billing-route rate limit with a predictable window.
- **Clock skew across requests** — `SlidingWindowCounter` uses `Date.now()` monotonically on the same process; no cross-request skew. If we ever replace with Redis ZADD-based sliding window, revisit.
- **Auth check caching** — `supabase.auth.getUser()` makes a network call to Supabase Auth. This is cached within the request's cookie context so repeat calls in the same request are cheap; no additional memoization needed for our single auth call.

**Test additions** (new `test/api-billing-invoices-ratelimit.test.ts`):

- First 10 requests in a minute → 200.
- 11th request → 429 with `Retry-After: 60`.
- Different users don't share the throttle (user A's 429 doesn't affect user B).
- Unauthenticated request → 401 without consuming a throttle slot.

## Acceptance Criteria

- [x] `invoice.paid` webhook is a no-op when current status is not `past_due` or `unpaid` (verified by unit tests for `cancelled` and `active` starting states).
- [x] `invoice.paid` still restores `past_due → active` and `unpaid → active` (no regression).
- [x] Past-due banner dismiss persists across same-tab reloads via sessionStorage.
- [x] Past-due banner re-appears in a fresh tab (sessionStorage is tab-scoped).
- [x] `sessionStorage` access is guarded against exceptions (private browsing).
- [x] WS `subscriptionStatus` cache is refreshed at least every `WS_SUBSCRIPTION_REFRESH_INTERVAL_MS` (default 60s) while a session is active.
- [x] A user suspended mid-session is closed within one refresh interval (≤60s by default) without requiring reconnect.
- [x] Refresh timer is cleared on session teardown (no leaked intervals — assertion in tests).
- [x] `GET /api/billing/invoices` returns 429 on the 11th request within a minute from the same authenticated user.
- [x] Rate limit is per-user (different users don't share the bucket).
- [x] Unauthenticated requests return 401 without consuming throttle slots.
- [x] All 1151+ existing tests still pass. (1314 pass, 1 pre-existing skip)
- [x] New tests for each of the four fixes pass.
- [x] `npx markdownlint-cli2 --fix` runs clean on this plan.

## Test Scenarios (TDD targets)

1. **Webhook guard — happy path**: `past_due` user gets `invoice.paid` → status becomes `active`.
2. **Webhook guard — the bug fix**: `cancelled` user gets `invoice.paid` (replay) → status remains `cancelled`.
3. **Webhook guard — active**: `active` user gets `invoice.paid` → status remains `active`, no error.
4. **Banner — fresh mount with key**: sessionStorage pre-populated → banner hidden on mount.
5. **Banner — dismiss then reload**: simulate two renders with sessionStorage write in between → hidden on second render.
6. **Banner — sessionStorage throw**: mock `setItem` to throw → `bannerDismissed` still true in state (in-memory), no uncaught error.
7. **WS refresh — tick to unpaid**: session cached `active`, DB updated to `unpaid`, tick timer → `checkSubscriptionSuspended` closes socket with code 4006.
8. **WS refresh — tick to same**: session `active`, DB still `active`, tick → no-op.
9. **WS refresh — DB error**: session `active`, DB throws, tick → cached value preserved, no close.
10. **WS refresh — teardown clears timer**: fake timers, session close → `clearInterval` called, no further ticks.
11. **Invoice rate limit — within budget**: 10 requests → all 200.
12. **Invoice rate limit — over budget**: 11th → 429 with `Retry-After`.
13. **Invoice rate limit — cross-user isolation**: user A bucket full, user B → 200.
14. **Invoice rate limit — unauth**: no token → 401, throttle not incremented.

## Alternative Approaches Considered

| Approach | Why not chosen |
|----------|----------------|
| Webhook guard: check-then-update (SELECT then UPDATE) | Introduces a race window between two DB calls. `UPDATE ... WHERE status IN (...)` is atomic. |
| Webhook guard: drop `invoice.paid` handler entirely | `customer.subscription.updated` carries `active` transitions, but the original handler was added as belt-and-suspenders. Keeping it is cheaper than re-litigating the design. |
| Banner dismiss: `localStorage` | Persists across tab closures — but the UX goal is to warn on every fresh session, so `sessionStorage` is correct. |
| Banner dismiss: server-side dismissal (users table column) | Overkill for a client-side UX preference; adds a migration and write path for no durable benefit. |
| WS cache: Supabase Realtime LISTEN on `users` table | Requires per-worker persistent realtime connection. Larger architectural change. Deferred; noted in Out of Scope. Current periodic refresh closes the TOCTOU window from "indefinite" to "≤60s". |
| WS cache: check on every message | Defeats the purpose of the cache (reintroduces the per-message DB query the cache was added to avoid). |
| Invoice rate limit: middleware-based | The project's rate limit pattern so far is local per route (share endpoint, WS). Keep consistency. |
| Invoice rate limit: IP-based | User-ID keying is strictly better for authenticated endpoints — avoids shared-IP collateral damage. |

## Risks & Rollback

- **Risk:** `.in()` filter on `.update()` behaves differently than expected in our Supabase JS client version. Mitigation: the TDD step verifies the generated SQL through tests that mock the `.eq().in()` chain and assert the expected filter. If the chain fails to compile, fall back to an atomic SQL function or a single-row fetch-then-update with `.eq("subscription_status", "past_due").or("subscription_status.eq.unpaid")`.
- **Risk:** `setInterval` leaks if a session teardown path is missed. Mitigation: add assertion tests that verify `clearInterval` is called on every teardown path (normal close, idle, disconnect grace expiry, subscription suspension close). `.unref()` so test processes exit cleanly.
- **Risk:** Over-aggressive rate limit (10/min) blocks a legitimate power user. Mitigation: env-configurable. Also, the endpoint sets `Cache-Control: private, max-age=300` so repeated loads within 5 min hit the browser cache and never reach the server.
- **Rollback:** Each fix is independent. If any causes production issues, revert the specific file via `git revert` of the relevant hunks — no cross-fix coupling.

## Relevant Project Learnings

These learnings from `knowledge-base/project/learnings/` apply directly to this plan and must be cross-referenced during implementation:

| Learning | Applies to | Action |
|----------|-----------|--------|
| `2026-04-13-ws-session-cache-subscription-status.md` | #2104 | Establishes the cache-at-auth pattern this fix extends. The learning's closing line ("The worst case with caching is a brief window...") is exactly what #2104 closes. |
| `2026-03-20-websocket-first-message-auth-toctou-race.md` | #2104 | **Mandatory pattern**: guard `ws.readyState !== WebSocket.OPEN` after any `await` before mutating session state. Already integrated into §4.1 above. |
| `2026-03-27-ws-session-race-abort-before-replace.md` | #2104 | Reinforces the abort-before-replace pattern. Our refresh timer's `checkSubscriptionSuspended` call follows this — `close()` aborts the session cleanly. Also warns about `vi.mock` vs bun — not relevant to this project (vitest only) but noted. |
| `2026-04-05-graceful-sigterm-shutdown-node-patterns.md` | #2104 | The SIGTERM handler iterates `wss.clients` — ensure it also clears `subscriptionRefreshTimer` on each session, or relies on `.unref()` to let the process exit (both are belt-and-suspenders). |
| `2026-04-13-stripe-status-mapping-check-constraint.md` | #2102 | Status enum in DB is `active | cancelled | past_due | unpaid | incomplete | null`. The`.in([past_due, unpaid])` filter respects this enum — no constraint violation path. |
| `2026-04-07-code-review-batch-ws-validation-error-logging-concurrency-comments.md` | #2104 | No empty catch blocks at system boundaries. Our refresh-timer `try/catch` logs via `log.warn`. Compliant. |
| `2026-04-13-billing-review-findings-batch-fix.md` | All | Established that grouping multiple billing code-review fixes into one PR is the project-approved pattern. Precedent for this PR. |
| `2026-02-12-review-compound-before-commit-workflow.md` | Phase 7 | Run `skill: soleur:compound` before shipping PR. Already in `tasks.md` Phase 7.2. |
| `2026-03-18-stop-hook-toctou-race-fix.md` | #2102 | Defense-in-depth TOCTOU template — we use the atomic `UPDATE ... WHERE IN (...)` variant which closes the race at the DB level, avoiding the need for multi-layer re-checks. |

## Domain Review

**Domains relevant:** CTO (Engineering)

### Engineering (CTO)

**Status:** reviewed (self)
**Assessment:** All four fixes land in well-established patterns in this codebase: Stripe webhook handling, React client-side state, the existing `SlidingWindowCounter` rate-limit primitive, and `ClientSession` cache management. No new patterns, no new dependencies. The TOCTOU fix (#2104) is the only one with a non-trivial design choice — we pick periodic refresh over realtime invalidation because the existing infrastructure doesn't have a realtime channel to reuse, and a 60s window is acceptable for the business problem (unpaid enforcement). No CPO/CMO/COO concerns: no user-facing surface changes (#2103 is a bug fix to an existing banner; no copy change), no pricing/packaging changes, no new expense.

No Product/UX Gate required (no new user-facing pages, no new flows, no new components). #2103 is a bug-fix on an existing banner's dismiss state — ADVISORY at most — but it does not change copy, layout, or interactions, so no UX artifacts needed.

## SpecFlow Notes

- All four fixes have clear, orthogonal acceptance criteria with no cross-dependencies.
- The only cross-cutting concern is the TDD order: write tests per fix, then implement, then run the full suite. Do not batch implementations without tests in between — the four fixes touch four different files so the usual "test-first" discipline is easy to maintain.
- **Edge case flagged:** `invoice.paid` events can arrive for subscriptions with `subscription_status = null` (trial users who somehow paid an invoice before `customer.subscription.updated` fired). With the new `.in([past_due, unpaid])` filter, these become no-ops. That is safer than the previous unconditional flip, but worth noting so the implementer doesn't add a null-handling branch by mistake.
- **Edge case flagged:** WS refresh timer should run even when no chat is in progress — the whole point is to catch suspension on an otherwise-idle authenticated session. Ensure `startSubscriptionRefresh` is called at the same auth gate as `sessions.set`, not inside a per-message handler.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-14-fix-billing-hardening-plan.md

Context: branch feat-fix-billing-hardening, worktree .worktrees/feat-fix-billing-hardening/.
Issues: #2102, #2103, #2104, #2105. PR: not yet opened.
Plan reviewed, implementation next. TDD per fix, then /ship.
```
