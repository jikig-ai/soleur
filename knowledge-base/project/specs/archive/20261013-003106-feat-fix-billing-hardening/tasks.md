# Tasks: fix(billing): harden webhooks, WS cache, and invoice endpoint

**Plan:** `knowledge-base/project/plans/2026-04-14-fix-billing-hardening-plan.md`
**Issues:** #2102, #2103, #2104, #2105

## Phase 1: Setup

- [ ] 1.1 Confirm on `feat-fix-billing-hardening` branch in worktree
- [ ] 1.2 Verify test runner resolves locally: `node node_modules/vitest/vitest.mjs run --reporter=dot test/stripe-webhook-invoice.test.ts` (sanity check)

## Phase 2: #2102 — Guard invoice.paid handler

### 2.1 Failing tests first (RED)

- [ ] 2.1.1 In `test/stripe-webhook-invoice.test.ts`, add test: `invoice.paid` on `cancelled` user leaves status unchanged
- [ ] 2.1.2 Add test: `invoice.paid` on `past_due` user sets `active` (regression guard)
- [ ] 2.1.3 Add test: `invoice.paid` on `unpaid` user sets `active` (regression guard)
- [ ] 2.1.4 Add test: `invoice.paid` on `active` user is a no-op (no error, no change)
- [ ] 2.1.5 Run tests — confirm the `cancelled` and `active` tests fail for the right reason

### 2.2 Implementation (GREEN)

- [ ] 2.2.1 In `app/api/webhooks/stripe/route.ts` case `"invoice.paid"`, append `.in("subscription_status", ["past_due", "unpaid"])` to the update chain
- [ ] 2.2.2 Update existing passing tests' mock expectations if needed (add `.in()` to the chain fluent mock)
- [ ] 2.2.3 Run all webhook tests — all green

## Phase 3: #2103 — sessionStorage banner dismiss

### 3.1 Failing tests first (RED)

- [ ] 3.1.1 Pick location: extend `test/billing-section.test.tsx` with a layout-dismiss block, OR create `test/dashboard-layout-banner.test.tsx`
- [ ] 3.1.2 Add test: banner visible when `past_due` and sessionStorage empty
- [ ] 3.1.3 Add test: banner hidden when `past_due` and sessionStorage key set
- [ ] 3.1.4 Add test: clicking dismiss sets sessionStorage key and hides banner
- [ ] 3.1.5 Add test: `sessionStorage.setItem` throwing is swallowed (jsdom mock)
- [ ] 3.1.6 Run — confirm initial fail

### 3.2 Implementation (GREEN)

- [ ] 3.2.1 In `app/(dashboard)/layout.tsx`, add `BANNER_DISMISS_KEY` constant
- [ ] 3.2.2 Add `useEffect` hydration from sessionStorage
- [ ] 3.2.3 Add `dismissBanner()` helper with try/catch around `sessionStorage.setItem`
- [ ] 3.2.4 Replace inline `setBannerDismissed(true)` in the button `onClick` with `dismissBanner`
- [ ] 3.2.5 Run tests — all green

## Phase 4: #2104 — WS subscription cache refresh

### 4.1 Failing tests first (RED)

- [ ] 4.1.1 Create or extend a focused test (e.g., `test/ws-subscription-refresh.test.ts` if not present) using `vi.useFakeTimers()`
- [ ] 4.1.2 Test: tick timer and DB returns `unpaid` → connection closed with code 4006
- [ ] 4.1.3 Test: tick timer and DB returns `active` (unchanged) → no close
- [ ] 4.1.4 Test: tick timer and DB throws → cached value preserved, no close
- [ ] 4.1.5 Test: session teardown clears the refresh timer (assert `clearInterval` called / timer no longer fires after teardown)
- [ ] 4.1.6 Run — confirm fail

### 4.2 Implementation (GREEN)

- [ ] 4.2.1 Add `WS_SUBSCRIPTION_REFRESH_INTERVAL_MS` config in `server/ws-handler.ts` near `WS_IDLE_TIMEOUT_MS`
- [ ] 4.2.2 Add `subscriptionRefreshTimer?` to `ClientSession` interface
- [ ] 4.2.3 Implement `refreshSubscriptionStatus(userId, session)` helper
- [ ] 4.2.4 Implement `startSubscriptionRefresh(userId, session)` helper (calls `setInterval`, stores on session, `.unref()`)
- [ ] 4.2.5 Call `startSubscriptionRefresh` right after `sessions.set(userId, newSession)` at auth completion
- [ ] 4.2.6 Ensure `session.subscriptionRefreshTimer` is cleared on every teardown path: normal close, idle timeout, disconnect grace expiry, subscription-suspended close. Grep for places that clear `idleTimer` and add `subscriptionRefreshTimer` cleanup alongside.
- [ ] 4.2.7 Run tests — all green

## Phase 5: #2105 — Invoice endpoint rate limit

### 5.1 Failing tests first (RED)

- [ ] 5.1.1 Create `test/api-billing-invoices-ratelimit.test.ts`
- [ ] 5.1.2 Test: 10 sequential requests → all 200
- [ ] 5.1.3 Test: 11th → 429 with `Retry-After: 60`
- [ ] 5.1.4 Test: user A over limit, user B under limit → A 429, B 200
- [ ] 5.1.5 Test: unauthenticated → 401 without burning throttle slot (verify by submitting 12 unauth requests, then 1 auth request → 200)
- [ ] 5.1.6 Run — confirm fail

### 5.2 Implementation (GREEN)

- [ ] 5.2.1 In `server/rate-limiter.ts`, add `invoiceEndpointThrottle` singleton and prune interval (`.unref()`)
- [ ] 5.2.2 In `app/api/billing/invoices/route.ts`, import the throttle + `logRateLimitRejection`
- [ ] 5.2.3 After auth check (401), add `isAllowed(user.id)` check returning 429 with `Retry-After: 60`
- [ ] 5.2.4 Run tests — all green

## Phase 6: Final Verification

- [ ] 6.1 Run full web-platform test suite: `node node_modules/vitest/vitest.mjs run` — all green (1151+ existing + new tests)
- [ ] 6.2 Run `npx markdownlint-cli2 --fix` on the plan and tasks files
- [ ] 6.3 Manual smoke: start dev server, confirm dashboard loads and past-due banner flow behaves as expected (if Stripe test data available)
- [ ] 6.4 Push branch: `git push -u origin feat-fix-billing-hardening`

## Phase 7: Ship

- [ ] 7.1 `skill: soleur:review` (multi-agent review on pushed branch)
- [ ] 7.2 `skill: soleur:compound` (capture any learnings)
- [ ] 7.3 `skill: soleur:ship` with PR body containing:
  - `Closes #2102`
  - `Closes #2103`
  - `Closes #2104`
  - `Closes #2105`
- [ ] 7.4 Poll PR state until MERGED
- [ ] 7.5 `cleanup-merged`
