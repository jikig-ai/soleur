# fix(billing): harden webhooks, WS cache, and invoice endpoint

**Date:** 2026-04-14
**Branch:** `feat-fix-billing-hardening`
**Worktree:** `.worktrees/feat-fix-billing-hardening`
**Closes:** #2102, #2103, #2104, #2105
**Source:** Deferred P3 items from code review of PR #2081 (tracked in review issue #2099)

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

**Verification note:** PostgREST `.in()` on `.update()` is supported and translates to `WHERE status IN (...)` on the UPDATE statement. Confirm against the Supabase JS client version in use before shipping — the project is on a recent `@supabase/supabase-js`. The plan-review agent and implementation TDD step should both verify the exact syntax compiles and the resulting `filter` is applied (not dropped).

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

**Test additions** (new `test/api-billing-invoices-ratelimit.test.ts`):

- First 10 requests in a minute → 200.
- 11th request → 429 with `Retry-After: 60`.
- Different users don't share the throttle (user A's 429 doesn't affect user B).
- Unauthenticated request → 401 without consuming a throttle slot.

## Acceptance Criteria

- [ ] `invoice.paid` webhook is a no-op when current status is not `past_due` or `unpaid` (verified by unit tests for `cancelled` and `active` starting states).
- [ ] `invoice.paid` still restores `past_due → active` and `unpaid → active` (no regression).
- [ ] Past-due banner dismiss persists across same-tab reloads via sessionStorage.
- [ ] Past-due banner re-appears in a fresh tab (sessionStorage is tab-scoped).
- [ ] `sessionStorage` access is guarded against exceptions (private browsing).
- [ ] WS `subscriptionStatus` cache is refreshed at least every `WS_SUBSCRIPTION_REFRESH_INTERVAL_MS` (default 60s) while a session is active.
- [ ] A user suspended mid-session is closed within one refresh interval (≤60s by default) without requiring reconnect.
- [ ] Refresh timer is cleared on session teardown (no leaked intervals — assertion in tests).
- [ ] `GET /api/billing/invoices` returns 429 on the 11th request within a minute from the same authenticated user.
- [ ] Rate limit is per-user (different users don't share the bucket).
- [ ] Unauthenticated requests return 401 without consuming throttle slots.
- [ ] All 1151+ existing tests still pass.
- [ ] New tests for each of the four fixes pass.
- [ ] `npx markdownlint-cli2 --fix` runs clean on this plan.

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
