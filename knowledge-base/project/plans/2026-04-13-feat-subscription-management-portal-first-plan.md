---
title: "feat: subscription management (portal-first)"
type: feat
date: 2026-04-13
---

# feat: subscription management (portal-first)

## Overview

Wire Stripe Customer Portal for cancel + payment method management. Add
webhook handlers for subscription lifecycle events. Display billing status
in Settings with a pre-cancel retention modal showing compounding knowledge.

Scope is deliberately limited: portal-first, no custom upgrade/downgrade UI,
no discount-based retention. Upgrade/downgrade deferred until pricing tiers
are committed (#2037).

## Problem Statement

- Billing page links to hardcoded `https://billing.stripe.com/p/login/test`
- No `customer.subscription.updated` webhook handler
- Missing DB columns: `stripe_subscription_id`, `current_period_end`,
  `cancel_at_period_end`
- Checkout creates duplicate Stripe customers (uses `customer_email` instead
  of `customer` param)
- Billing page is standalone — not integrated with Settings
- No retention mechanism at cancellation

## Proposed Solution

### Architecture

```text
┌─────────────────────────────────────────────────────┐
│ Settings Page (existing)                            │
│                                                     │
│  ┌─ Account ─┐ ┌─ Project ─┐ ┌─ API Key ─┐        │
│  └───────────┘ └───────────┘ └───────────┘        │
│  ┌─ Connected Services ─┐                          │
│  └──────────────────────┘                          │
│  ┌─ Billing (NEW) ──────────────────────────────┐  │
│  │ Plan: Solo ($49/mo)        [Active] badge    │  │
│  │ Billing period ends: May 13, 2026            │  │
│  │ [Manage Subscription]  ← opens portal        │  │
│  │ [Cancel Subscription]  ← opens retention     │  │
│  │                            modal first       │  │
│  └──────────────────────────────────────────────┘  │
│  ┌─ Danger Zone ─┐                                 │
│  └───────────────┘                                 │
└─────────────────────────────────────────────────────┘

Cancel flow:
  User clicks "Cancel" → Retention modal (KB count, convos, services)
  → "Keep my account" (close modal) | "Continue to cancel" (→ Stripe Portal)

Portal flow:
  User clicks "Manage" → POST /api/billing/portal → 302 → Stripe Portal
  → Stripe handles cancel/payment method → webhook fires → DB updated
```

### Data Flow

```text
Stripe Portal action
  → Stripe fires webhook (customer.subscription.updated or .deleted)
  → POST /api/webhooks/stripe
  → Verify signature
  → Extract subscription data
  → Update users table (service role)
  → User refreshes Settings → sees updated status
```

### Implementation Phases

#### Phase 1: Cleanup + Database + Webhook Foundation

**Delete standalone billing page first**

File: `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`

Delete this file. Its functionality is replaced by the Settings billing
section. API usage display deferred to invoice history (#1079).

**Migration: add billing columns**

File: `apps/web-platform/supabase/migrations/018_subscription_billing_columns.sql`

```sql
-- Add billing columns for subscription lifecycle tracking.
-- These columns are NOT in the authenticated GRANT list (migration 006),
-- so they are automatically service-role-only.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text,
  ADD COLUMN IF NOT EXISTS current_period_end timestamptz,
  ADD COLUMN IF NOT EXISTS cancel_at_period_end boolean NOT NULL DEFAULT false;
```

No RLS changes needed — migration 006 already does `REVOKE UPDATE ON
TABLE public.users FROM authenticated` and only grants `UPDATE (email)`.
New columns inherit the restriction automatically.

**Verify migration number:** Check the latest migration file number in
`apps/web-platform/supabase/migrations/` and use the next sequential
number. The `018` above is a placeholder.

**Webhook expansion**

File: `apps/web-platform/app/api/webhooks/stripe/route.ts`

Add `customer.subscription.updated` handler:

- Extract subscription ID, status, `cancel_at_period_end`,
  `current_period_end` from the event
- Update users table by `stripe_customer_id` match
- For `checkout.session.completed`: also store `stripe_subscription_id`
  (extract from `session.subscription`)
- For `customer.subscription.deleted`: set `subscription_status` to
  `'cancelled'`, `cancel_at_period_end = false`, clear
  `current_period_end`

No explicit idempotency mechanism needed — all webhook handlers use
`UPDATE ... SET` which is naturally idempotent (running twice produces
the same result). Add event deduplication only if webhook replays cause
observable issues.

**Fix duplicate Stripe customers**

File: `apps/web-platform/app/api/checkout/route.ts`

Before creating a checkout session, query the user's
`stripe_customer_id` from the users table. If it exists, pass `customer`
instead of `customer_email` to `checkout.sessions.create()`:

```typescript
// Pseudocode — not implementation
const { data: userData } = await serviceClient
  .from("users")
  .select("stripe_customer_id")
  .eq("id", user.id)
  .single();

const sessionParams = {
  mode: "subscription" as const,
  line_items: [{ price: process.env.STRIPE_PRICE_ID!, quantity: 1 }],
  success_url: `...`,
  cancel_url: `...`,
  metadata: { supabase_user_id: user.id },
  ...(userData?.stripe_customer_id
    ? { customer: userData.stripe_customer_id }
    : { customer_email: user.email }),
};
```

This requires switching from the cookie-based `createClient()` to
`createServiceClient()` for the user lookup (or using the existing
auth'd client since the users table has a SELECT policy). Use the
cookie client since `users` has `Users can read own profile` SELECT
policy.

#### Phase 2: Portal API Route

**New route: `/api/billing/portal`**

File: `apps/web-platform/app/api/billing/portal/route.ts`

```typescript
// Pseudocode — not implementation
export async function POST(request: Request) {
  // 1. CSRF validation (state-mutating, authenticated)
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/billing/portal", origin);

  // 2. Auth check
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  // 3. Get Stripe customer ID
  const { data: userData } = await supabase
    .from("users")
    .select("stripe_customer_id")
    .eq("id", user.id)
    .single();

  if (!userData?.stripe_customer_id) {
    return NextResponse.json({ error: "No subscription" }, { status: 400 });
  }

  // 4. Create portal session
  const portalSession = await getStripe().billingPortal.sessions.create({
    customer: userData.stripe_customer_id,
    return_url: `${appOrigin}/dashboard/settings`,
  });

  return NextResponse.json({ url: portalSession.url });
}
```

**CSRF coverage test update**

File: `apps/web-platform/lib/auth/csrf-coverage.test.ts`

The new `/api/billing/portal` route uses `validateOrigin` — it should
NOT be added to `EXEMPT_ROUTES`. The CSRF coverage test will
automatically detect it and verify it has CSRF protection. No test
changes needed unless the test fails (which would indicate missing CSRF
in the route).

#### Phase 3: Settings Billing Section

**Settings page data fetching**

File: `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`

Add billing data to the server component's data fetch:

```typescript
// Add to existing service client queries
const { data: billingData } = await service
  .from("users")
  .select("subscription_status, stripe_customer_id, current_period_end, cancel_at_period_end")
  .eq("id", user.id)
  .single();
```

Pass billing props to `SettingsContent`.

**Billing section component**

File: `apps/web-platform/components/settings/billing-section.tsx`

New component following the existing Settings card pattern:

- Subscription status badge (Active / Cancelled / Cancelling / None)
  - "Cancelling" shown when `cancel_at_period_end = true` and
    `subscription_status = 'active'`
- Plan name and price (hardcoded "Solo — $49/mo" for single tier)
- Billing period end date (formatted from `current_period_end`)
- "Manage Subscription" button → POST to `/api/billing/portal` → redirect
- "Cancel Subscription" button → opens retention modal
- If no subscription: "Subscribe" button → POST to `/api/checkout` → redirect
- If `cancel_at_period_end`: show banner "Your subscription will end on
  [date]. You'll retain full access until then." with "Reactivate" link
  (→ portal)

Styling: Same card pattern as other Settings sections
(`rounded-xl border border-neutral-800 bg-neutral-900/50 p-6`).

**Retention modal component**

File: `apps/web-platform/components/settings/cancel-retention-modal.tsx`

Modal overlay shown when user clicks "Cancel Subscription":

- Heading: "Before you go..."
- Stats display (fetched from existing tables):
  - KB artifact count (from `knowledge-base` API or conversations table)
  - Conversation count
  - Connected service count (from `service_tokens` table)
  - Days since signup (from `users.created_at`)
- Primary CTA: "Keep my account" → closes modal
- Secondary CTA: "Continue to cancel" → POST `/api/billing/portal` →
  redirect to Stripe Portal where actual cancellation happens

Stats are fetched server-side in the Settings page and passed as props
(already fetching data there — add count queries for conversations,
service tokens, and KB entries alongside billing data).

#### Phase 4: Tests

**Test coverage**

Files:

- `apps/web-platform/test/billing-section.test.tsx` — component render
  tests for billing section (active, cancelled, cancelling, no sub)
- `apps/web-platform/test/api-billing-portal.test.ts` — portal route
  tests (auth, CSRF, no customer ID, success redirect)
- `apps/web-platform/test/webhook-subscription.test.ts` — webhook
  handler tests (subscription.updated, deleted, checkout.completed with
  subscription ID)
- `apps/web-platform/test/agent-env.test.ts` — verify no Stripe vars
  leak (may already be covered)

Test runner: Check `package.json scripts.test` — project uses vitest.

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|-------------|
| Full custom cancel/upgrade/downgrade UI | 0 users, 1 tier, speculative. Portal handles it. |
| Separate subscriptions table | Adds join to every auth check. Users table + RLS fix is simpler. Migration 006 already provides the fix. |
| Stripe Customer Portal only (no interstitial) | Loses retention opportunity. Modal is minimal additional work. |
| Billing as top-level sidebar item | Users visit billing rarely. Settings sub-section is the right home. |
| SECURITY DEFINER function for billing writes | Migration 006 column allowlist is simpler and already in place. |

## Acceptance Criteria

### Functional Requirements

- [ ] `POST /api/billing/portal` creates Stripe billing portal session
      and returns redirect URL
- [ ] Pre-cancel retention modal shows KB artifact count, conversation
      count, connected service count, and days since signup
- [ ] Retention modal "Keep my account" closes modal, "Continue to
      cancel" redirects to Stripe portal
- [ ] `customer.subscription.updated` webhook updates `subscription_status`,
      `cancel_at_period_end`, `current_period_end`
- [ ] `checkout.session.completed` webhook stores `stripe_subscription_id`
- [ ] Settings billing section shows plan name, status badge, period end
      date, manage/cancel buttons
- [ ] Cancelling state shows banner with end date and reactivate link
- [ ] Checkout uses existing `stripe_customer_id` when available
- [ ] No subscription state: shows subscribe CTA in Settings billing
- [ ] Standalone `/dashboard/billing` page removed
- [ ] `customer.subscription.deleted` webhook sets `subscription_status`
      to `cancelled`, clears `cancel_at_period_end` and `current_period_end`
- [ ] Active subscriber who tries to subscribe again is blocked or
      redirected to manage (double-subscribe guard)
- [ ] `/dashboard/billing` URL returns redirect to `/dashboard/settings`
      (not 404 — users may have bookmarks)

### Non-Functional Requirements

- [ ] Billing columns not user-writable (verified by RLS — migration 006)
- [ ] No new Stripe env vars in agent subprocess (buildAgentEnv test)
- [ ] Portal route has CSRF protection (csrf-coverage.test.ts catches it)
- [ ] Webhook route remains CSRF-exempt (Stripe signature verification)

## Domain Review

**Domains relevant:** Product, Marketing, Engineering, Legal

Carried forward from brainstorm `2026-04-13-subscription-management-brainstorm.md`.

### Product (CPO)

**Status:** reviewed
**Assessment:** Portal-first scope approved. Upgrade/downgrade deferred
to #2037. Phase 3 exit criteria should note deferral. Middleware subscription
enforcement deferred to Phase 4 (#1162).

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Loss-aversion retention approved. No discount offers.
Cancellation copy must respect founder autonomy — no dark patterns. Current
billing page has zero brand alignment; rebuild in Settings.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Schema gaps, RLS fix, webhook idempotency, duplicate
Stripe customer all addressed in plan. Migration 006 already provides
column-level protection — no additional RLS migration needed.

### Legal (CLO)

**Status:** reviewed
**Assessment:** ToS Section 5 covers cancellation and grace period.
Upgrade/downgrade terms deferred with the feature (#2037).

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** none (brainstorm carry-forward — CPO and CMO
already assessed the billing section as a Settings sub-section, modal
retention pattern)
**Skipped specialists:** ux-design-lead (existing Settings card pattern
reused, no novel page layout), conversion-optimizer (CMO recommended but
deferred to post-launch when churn data exists)
**Pencil available:** N/A

## Test Scenarios

### Acceptance Tests

- Given an active subscriber, when they visit Settings, then they see
  billing section with plan name, Active badge, period end date, and
  Manage/Cancel buttons
- Given an active subscriber, when they click "Manage Subscription",
  then they are redirected to Stripe Customer Portal
- Given an active subscriber, when they click "Cancel Subscription",
  then they see a retention modal with KB count, conversation count,
  connected services count, and days since signup
- Given a retention modal is open, when user clicks "Keep my account",
  then the modal closes and no cancellation occurs
- Given a retention modal is open, when user clicks "Continue to cancel",
  then they are redirected to Stripe Portal to complete cancellation
- Given a user cancels via Stripe Portal, when `subscription.updated`
  webhook fires with `cancel_at_period_end: true`, then Settings shows
  "Cancelling" badge and banner with end date
- Given a cancelled user whose period has ended, when
  `subscription.deleted` webhook fires, then `subscription_status`
  becomes `cancelled` and Settings shows "Cancelled" badge
- Given a user with no subscription, when they visit Settings billing
  section, then they see "No active subscription" with a Subscribe button
- Given a user checks out twice, when the second checkout creates a
  session, then it reuses the existing `stripe_customer_id` (no duplicate)
- Given a duplicate `subscription.updated` webhook delivery, then the
  second update produces the same DB state (idempotent)

### Edge Cases

- Given a user whose `stripe_customer_id` is null, when they click
  "Manage Subscription", then they see an error message
- Given a `subscription.updated` webhook with unknown `stripe_customer_id`,
  then the handler logs a warning and returns 200
- Given the Stripe API is unavailable, when user clicks portal button,
  then they see an error message (not a crash)

## Dependencies & Risks

| Dependency | Risk | Mitigation |
|-----------|------|------------|
| Stripe test mode only | Low | Feature works in test mode. Live mode activation in Phase 4 (#1444). |
| Single price ID | Low | Portal works with one tier. Multi-tier deferred (#2037). |
| No middleware enforcement | Low | Access not gated on subscription status currently. Phase 4 (#1162). |

## References & Research

### Internal References

- Existing webhook handler: `apps/web-platform/app/api/webhooks/stripe/route.ts`
- Checkout route: `apps/web-platform/app/api/checkout/route.ts`
- Stripe client: `apps/web-platform/lib/stripe.ts`
- Settings page: `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`
- Settings content: `apps/web-platform/components/settings/settings-content.tsx`
- RLS column restriction: `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql`
- CSRF coverage test: `apps/web-platform/lib/auth/csrf-coverage.test.ts`
- Public paths: `apps/web-platform/lib/routes.ts`

### Institutional Learnings

- CSRF webhook exemption: `2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md`
- Process.env leak prevention: `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`
- RLS column grant override: `2026-03-20-supabase-column-level-grant-override.md`
- Server-side consent pattern: `2026-03-20-server-side-tc-acceptance-security-pattern.md`
- Async webhook timeout: `2026-03-21-async-webhook-deploy-cloudflare-timeout.md`
- Doppler patterns: `2026-03-20-doppler-secrets-manager-setup-patterns.md`

### Related Issues

- Pricing page: #656 (closed)
- Invoice history: #1079 (open, P2)
- Plan enforcement: #1162 (Phase 4)
- Stripe live mode: #1444 (Phase 4)
- Upgrade/downgrade: #2037 (deferred)
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-13-subscription-management-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-subscription-management/spec.md`
