# Tasks: Invoice History + Failed Payment Recovery

**Issue:** #1079
**Plan:** knowledge-base/project/plans/2026-04-13-feat-invoice-history-failed-payment-recovery-plan.md

## Phase 1: Migration + Webhook Handlers

- [ ] 1.1 Create migration `020_invoice_recovery.sql`
  - [ ] 1.1.1 Drop and recreate `subscription_status` CHECK constraint with `unpaid`
- [ ] 1.2 Add `customer.subscription.updated` handler (authoritative status source)
  - [ ] 1.2.1 Set `past_due` when subscription status is `past_due`
  - [ ] 1.2.2 Set `unpaid` when subscription status is `unpaid`
  - [ ] 1.2.3 Set `active` when subscription status is `active`
  - [ ] 1.2.4 Log when update affects 0 rows (orphaned customer)
- [ ] 1.3 Add `invoice.payment_failed` handler (log only, no status change)
- [ ] 1.4 Add `invoice.paid` handler (set `active`, belt-and-suspenders)
- [ ] 1.5 Fix existing handlers: destructure `{ data, error }` on all Supabase queries
- [ ] 1.6 Add `createPortalSession()` helper to `lib/stripe.ts`
- [ ] 1.7 Write tests: `test/stripe-webhook-invoice.test.ts`

## Phase 2: Billing Page (Portal + Invoices + Badges)

- [ ] 2.1 Create API route `app/api/billing/portal/route.ts`
- [ ] 2.2 Create API route for invoice list (inline or `app/api/billing/invoices/route.ts`)
- [ ] 2.3 Replace hardcoded portal link with dynamic portal session redirect
- [ ] 2.4 Add invoice list section (fetch, display, empty state)
- [ ] 2.5 Add `past_due` (orange) and `unpaid` (red/Suspended) status badges
- [ ] 2.6 Add recovery prompt for suspended state

## Phase 3: Banner + Middleware + WS Enforcement

- [ ] 3.1 Add payment banner inline in `app/(dashboard)/layout.tsx`
  - [ ] 3.1.1 Yellow warning for `past_due` (dismissible)
  - [ ] 3.1.2 Red alert for `unpaid` (not dismissible)
- [ ] 3.2 Combine middleware T&C query with subscription status (single SELECT)
- [ ] 3.3 Add middleware billing enforcement (block non-GET for unpaid, fail-open)
- [ ] 3.4 Add WS handler gate in `chat` message handler
- [ ] 3.5 Add WS handler gate in `resume_session` handler
- [ ] 3.6 Write tests: `test/billing-enforcement.test.ts`

## Post-Merge Verification

- [ ] 4.1 Verify migration applied to production via Supabase REST API
- [ ] 4.2 Verify Stripe webhook receives test events
- [ ] 4.3 Verify billing portal redirects dynamically
- [ ] 4.4 Verify invoice list displays test data
