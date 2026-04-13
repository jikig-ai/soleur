# Tasks: Subscription Management (Portal-First)

**Plan:** `knowledge-base/project/plans/2026-04-13-feat-subscription-management-portal-first-plan.md`
**Issue:** #1078
**Branch:** feat-subscription-management

## Phase 1: Database + Webhook Foundation

- [ ] 1.1 Create migration: add `stripe_subscription_id`, `current_period_end`,
      `cancel_at_period_end`, `current_plan` columns to users table
  - Check latest migration number in `apps/web-platform/supabase/migrations/`
  - Columns are auto-protected by migration 006 (no GRANT needed)
- [ ] 1.2 Expand webhook handler (`apps/web-platform/app/api/webhooks/stripe/route.ts`):
  - [ ] 1.2.1 Add `customer.subscription.updated` handler — update
        `subscription_status`, `cancel_at_period_end`, `current_period_end`,
        `current_plan` by `stripe_customer_id`
  - [ ] 1.2.2 Update `checkout.session.completed` handler — also store
        `stripe_subscription_id` from `session.subscription`
  - [ ] 1.2.3 Update `customer.subscription.deleted` handler — set
        `cancel_at_period_end = false`, clear `current_period_end`
- [ ] 1.3 Fix duplicate Stripe customers in checkout route
      (`apps/web-platform/app/api/checkout/route.ts`):
  - Query user's `stripe_customer_id` before creating session
  - Pass `customer` instead of `customer_email` if ID exists

## Phase 2: Portal API Route

- [ ] 2.1 Create `/api/billing/portal` route
      (`apps/web-platform/app/api/billing/portal/route.ts`):
  - CSRF validation via `validateOrigin`/`rejectCsrf`
  - Auth via `createClient` + `getUser`
  - Query `stripe_customer_id` from users table
  - Create `billingPortal.sessions.create()` with return_url to Settings
  - Return JSON with portal URL

## Phase 3: Settings Billing UI

- [ ] 3.1 Create billing section component
      (`apps/web-platform/components/settings/billing-section.tsx`):
  - Subscription status badge (Active / Cancelling / Cancelled / None)
  - Plan name + billing period end date
  - "Manage Subscription" button (→ portal)
  - "Cancel Subscription" button (→ retention modal)
  - Subscribe CTA for non-subscribers
  - Cancellation banner when `cancel_at_period_end = true`
- [ ] 3.2 Create retention modal component
      (`apps/web-platform/components/settings/cancel-retention-modal.tsx`):
  - Stats: KB artifact count, conversation count, connected services count,
    days since signup
  - "Keep my account" button (closes modal)
  - "Continue to cancel" button (→ portal redirect)
- [ ] 3.3 Add billing data to Settings server component
      (`apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`):
  - Fetch `subscription_status`, `stripe_customer_id`, `current_period_end`,
    `cancel_at_period_end`, `current_plan` from users table
  - Fetch stats counts (conversations, services)
  - Pass billing + stats props to `SettingsContent`
- [ ] 3.4 Add billing section to `SettingsContent`
      (`apps/web-platform/components/settings/settings-content.tsx`):
  - Add `BillingSection` between Connected Services and Danger Zone

## Phase 4: Cleanup + Tests

- [ ] 4.1 Delete standalone billing page
      (`apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`)
- [ ] 4.2 Write tests:
  - [ ] 4.2.1 Billing section component tests
        (`apps/web-platform/test/billing-section.test.tsx`)
  - [ ] 4.2.2 Portal route tests
        (`apps/web-platform/test/api-billing-portal.test.ts`)
  - [ ] 4.2.3 Webhook handler tests for new events
        (`apps/web-platform/test/webhook-subscription.test.ts`)
  - [ ] 4.2.4 Verify agent env isolation
        (`apps/web-platform/test/agent-env.test.ts`)
- [ ] 4.3 Run CSRF coverage test to verify `/api/billing/portal` is detected
- [ ] 4.4 Apply Supabase migration to dev/staging and verify via REST API
