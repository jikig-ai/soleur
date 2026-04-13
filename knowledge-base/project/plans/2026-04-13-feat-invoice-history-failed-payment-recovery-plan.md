---
title: "feat: invoice history + failed payment recovery"
type: feat
date: 2026-04-13
issue: 1079
branch: feat-invoice-recovery
brainstorm: knowledge-base/project/brainstorms/2026-04-13-invoice-recovery-brainstorm.md
spec: knowledge-base/project/specs/feat-invoice-recovery/spec.md
---

# Plan: Invoice History + Failed Payment Recovery

## Summary

Complete the billing trilogy by adding invoice history display, failed payment
detection via Stripe webhooks, an in-app recovery banner, and read-only mode
enforcement for unpaid subscriptions. Uses Stripe-native features throughout
(Smart Retries, Customer Portal, hosted PDFs, built-in emails).

**Ref #1079**

## Background

The pricing page (#656) and subscription management (#1078) are done. The
webhook handler (`apps/web-platform/app/api/webhooks/stripe/route.ts`) handles
only `checkout.session.completed` and `customer.subscription.deleted`. The DB
schema (`002_add_byok_and_stripe_columns.sql`) defines a `subscription_status`
CHECK constraint with `('none', 'active', 'cancelled', 'past_due')` but no
code ever sets `past_due`. The billing page
(`apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`) has a
hardcoded Stripe test portal URL.

### Key Learnings Applied

- CSRF: Stripe webhook route is already in `PUBLIC_PATHS` — no change needed
- Supabase silently swallows errors — every query must destructure `{ data, error }`
- Middleware fail-open for billing checks (per learnings doc)
- Unapplied migrations cause silent production failures — verify post-merge
- `customer.subscription.updated` is the authoritative source for subscription
  status transitions — `invoice.payment_failed` fires on every retry attempt
  and should not directly change status

### Review Changes Applied [Updated 2026-04-13]

Plan reviewed by DHH, Kieran, and code-simplicity reviewers. Changes applied:

- **Removed `stripe_events` idempotency table** — webhook handlers are
  idempotent by nature (setting same status is a no-op). Add if needed.
- **Removed `suspended_at` column** — YAGNI, needed only for deferred
  auto-deletion feature (#2088). Add when building that feature.
- **Fixed webhook event handling** — `invoice.payment_failed` no longer
  changes `subscription_status` directly. `customer.subscription.updated` is
  the authoritative source for `past_due`/`unpaid` transitions.
- **Collapsed 7 phases to 3** — webhook + migration, billing page, enforcement.
- **Reduced 6 test files to 2** — webhook tests + middleware/enforcement tests.
- **Combined middleware queries** — single `.select("tc_accepted_version, subscription_status")`
  call, not two separate queries.
- **Fixed WS gating location** — gate at `chat` message handler where
  `createConversation` is called, plus gate `resume_session`.
- **Removed `suspended/page.tsx`** — billing page handles suspended state.
- **Added invoice status filter** — exclude draft invoices from the list.

## Phases

### Phase 1: Migration + Webhook Handlers

**Files:**

- `apps/web-platform/supabase/migrations/020_invoice_recovery.sql` (new)
- `apps/web-platform/app/api/webhooks/stripe/route.ts` (modify)
- `apps/web-platform/lib/stripe.ts` (modify)
- `apps/web-platform/test/stripe-webhook-invoice.test.ts` (new)

**Migration (`020_invoice_recovery.sql`):**

```sql
-- Expand subscription_status CHECK constraint to include 'unpaid'
alter table public.users
  drop constraint if exists users_subscription_status_check;

alter table public.users
  add constraint users_subscription_status_check
  check (subscription_status in ('none', 'active', 'cancelled', 'past_due', 'unpaid'));
```

That's it — no new columns, no new tables. The existing `subscription_status`
column handles all states.

**Webhook handler changes:**

Add three new event cases to the existing `switch` block. All updates use
`.eq("stripe_customer_id", customerId)` — if no matching user, zero rows
affected (safe no-op, but log for observability).

1. `customer.subscription.updated` — the **authoritative** source for status:
   - Read `subscription.status` from the event object
   - If `past_due` → set `subscription_status = 'past_due'`
   - If `unpaid` → set `subscription_status = 'unpaid'`
   - If `active` → set `subscription_status = 'active'`
   - Log when update affects 0 rows (orphaned customer)

2. `invoice.payment_failed` — **notification signal only**, does NOT change
   `subscription_status`. Log the event for observability. Stripe's built-in
   emails handle user notification. (Stripe fires this on every retry attempt,
   not just the final failure.)

3. `invoice.paid` — set `subscription_status = 'active'` (belt-and-suspenders
   alongside `customer.subscription.updated`)

**Add error checking to existing handlers:** The current `checkout.session.completed`
and `customer.subscription.deleted` handlers do not destructure `{ data, error }`.
Fix them to check errors (per learnings).

**Add portal session helper to `lib/stripe.ts`:**

```typescript
export async function createPortalSession(
  customerId: string,
  returnUrl: string,
): Promise<string> {
  const session = await getStripe().billingPortal.sessions.create({
    customer: customerId,
    return_url: returnUrl,
  });
  return session.url;
}
```

**Tests (`test/stripe-webhook-invoice.test.ts`):**

- `customer.subscription.updated` with `past_due` sets status
- `customer.subscription.updated` with `unpaid` sets status
- `customer.subscription.updated` with `active` restores status
- `invoice.payment_failed` does NOT change status (log only)
- `invoice.paid` sets `active`
- Duplicate event with same status is no-op (idempotent update)
- No matching user logs warning, returns 200
- Invalid signature returns 400

### Phase 2: Billing Page (Portal + Invoices + Badges)

**Files:**

- `apps/web-platform/app/api/billing/portal/route.ts` (new)
- `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx` (modify)

**Portal API route (`app/api/billing/portal/route.ts`):**

1. Get authenticated user via Supabase
2. Look up `stripe_customer_id` from `users` table
3. Call `createPortalSession()` with customer ID and return URL
4. Return `{ url }` for client-side redirect

**Billing page updates:**

1. **Replace hardcoded portal link** — "Manage subscription" button calls
   `/api/billing/portal` and redirects to the dynamic URL

2. **Add invoice list section** — fetch invoices server-side via
   `getStripe().invoices.list({ customer, limit: 24, status: "paid" })`
   (exclude draft invoices). Display below subscription card:
   - Date (formatted)
   - Amount
   - Status badge
   - "View" → `hosted_invoice_url`
   - "PDF" → `invoice_pdf`
   - Empty state: "No invoices yet."

   Since this is a client component, fetch via a new inline API call to
   `/api/billing/invoices`. Create a minimal route handler that calls
   Stripe and returns the mapped array.

3. **Add status badges** — update `SubscriptionStatus` type to include
   `past_due` and `unpaid`. Add badge variants:
   - `past_due`: orange "Past Due"
   - `unpaid`: red "Suspended"

4. **Show recovery prompt for suspended state** — when `unpaid`, show a
   prominent card explaining read-only mode with a "Resolve payment" button
   linking to the portal.

No separate test file — portal route is a thin Stripe pass-through, invoice
list is a Stripe API call, badges are presentational. Covered by the existing
`billing-cost-list.test.tsx` pattern for the billing page.

### Phase 3: Banner + Middleware + WS Enforcement

**Files:**

- `apps/web-platform/app/(dashboard)/layout.tsx` (modify)
- `apps/web-platform/middleware.ts` (modify)
- `apps/web-platform/server/ws-handler.ts` (modify)
- `apps/web-platform/test/billing-enforcement.test.ts` (new)

**Payment banner (inline in layout):**

Add a conditional banner in the `<main>` area of `app/(dashboard)/layout.tsx`,
above `{children}`. Approximately 15-20 lines of JSX:

- Yellow warning for `past_due` (dismissible): "Your last payment failed.
  Update your payment method to avoid service interruption." + button
- Red alert for `unpaid` (not dismissible): "Your subscription is unpaid.
  Your account is in read-only mode." + button
- Fetch `subscription_status` in the existing `useEffect` (layout already
  queries Supabase for admin check — add status to that flow)

**Middleware changes:**

Combine the T&C query with subscription status in a single call. After the
existing T&C check block (line ~113), modify the query:

```typescript
// Replace: .select("tc_accepted_version")
// With:    .select("tc_accepted_version, subscription_status")
```

After the T&C redirect check, add the billing enforcement check (same
pattern, ~10 lines):

- If `subscription_status === 'unpaid'` AND request method is not `GET`:
  - If path starts with `/api/billing` or `/api/checkout` → allow
  - Otherwise → return 403 JSON `{ error: "subscription_suspended" }`
- Fail-open: already handled by the existing `tcError` check (same query)

**WebSocket handler changes:**

Two gating points in `ws-handler.ts`:

1. **Before `createConversation`** (line ~345 in `chat` handler): query
   `subscription_status`. If `unpaid`, send error message and close with
   `WS_CLOSE_CODES.POLICY_VIOLATION`.

2. **In `resume_session` handler**: same check — unpaid users cannot resume
   conversations either.

**Tests (`test/billing-enforcement.test.ts`):**

- Middleware: `unpaid` user GET passes through
- Middleware: `unpaid` user POST to `/api/` returns 403
- Middleware: `unpaid` user POST to `/api/billing/portal` passes through
- Middleware: `active` user is unaffected
- Middleware: query error fails open
- WS: `unpaid` user `chat` message returns error and closes connection
- WS: `unpaid` user `resume_session` returns error and closes connection
- WS: `active` user can chat normally

### Post-Merge Verification

Not a code phase — part of standard post-merge workflow (per AGENTS.md):

1. Verify migration applied via Supabase REST API (`unpaid` in CHECK constraint)
2. Send test webhook events via Stripe dashboard
3. Verify billing portal redirects dynamically (not hardcoded test URL)
4. Verify invoice list displays test data

## Acceptance Criteria

- [ ] Invoice list displays with PDF download links (FR1, FR2)
- [ ] In-app banner shows for `past_due` and `unpaid` (FR3, FR4)
- [ ] Read-only mode enforced when `unpaid` (FR5)
- [x] Webhook handles `customer.subscription.updated` for all status transitions (FR6, FR7)
- [x] `invoice.payment_failed` logged but does not change status
- [x] Webhook handles `invoice.paid` → `active` (FR8)
- [x] Webhook updates are idempotent (no stripe_events table needed) (FR9)
- [ ] Portal sessions are dynamic (FR10)
- [ ] Middleware fails open on query error (TR5)
- [ ] WS handler gates both `chat` and `resume_session` for unpaid users
- [ ] Migration applied to production post-merge (TR8)

## Domain Review

**Domains relevant:** Product, Marketing, Engineering, Finance

Carried forward from brainstorm domain assessments (2026-04-13).

### Product (CPO)

**Status:** reviewed
**Assessment:** Prerequisite for Phase 4 Stripe live mode. Key decisions
resolved in brainstorm: read-only grace period, Stripe-managed retry schedule.

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Table stakes for B2B SaaS. No custom copy needed for MVP
(Stripe built-in emails). Invoice history removes conversion objection.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Stripe-native approach. Extend existing `subscription_status`
column. Use `customer.subscription.updated` as authoritative status source.

### Finance (CFO)

**Status:** reviewed
**Assessment:** Zero incremental cost. Highest-ROI revenue protection at
1-2 user scale.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (brainstorm carry-forward)
**Agents invoked:** none (Stripe-native UI — portal redirect + invoice list)
**Skipped specialists:** ux-design-lead (minimal custom UI), copywriter
(Stripe handles emails)
**Pencil available:** N/A

## Alternative Approaches Considered

| Approach | Why Not |
|----------|---------|
| Custom card-update form (Stripe Elements) | PCI SAQ-A compliance, 2x scope |
| Local invoice DB table | Stale data risk, unnecessary migration |
| Custom Resend emails | Zero users yet, Stripe emails are free |
| Full lockout on unpaid | Risks permanent churn, destroys trust |
| stripe_events idempotency table | YAGNI — updates are already idempotent |
| suspended_at column | YAGNI — deferred to #2088 auto-deletion feature |

## Build Sequence

```text
Phase 1 (migration + webhooks + stripe helpers)
  → Phase 2 (billing page: portal + invoices + badges)
    → Phase 3 (banner + middleware + WS enforcement)
      → Post-merge verification
```

Phase 2 depends on Phase 1 (portal helper). Phase 3 depends on Phase 1
(subscription_status transitions must exist before enforcement).
