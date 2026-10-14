# Spec: Subscription Management (Portal-First)

**Issue:** #1078
**Branch:** feat-subscription-management
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-13-subscription-management-brainstorm.md`
**Phase:** 3 (Make it Sticky)
**Priority:** P1

## Problem Statement

Founders cannot manage their subscription without contacting support. The
billing page links to a hardcoded Stripe test portal URL and has no cancel
flow, retention mechanism, or subscription status detail. Billing columns on
the users table are user-writable via RLS, creating a security vulnerability.

## Goals

1. Founders can cancel their subscription via Stripe Customer Portal
2. Pre-cancel interstitial shows compounding knowledge to encourage retention
3. Billing state is accurately tracked via webhook handlers
4. Billing columns are protected from client-side writes
5. Subscription status and billing info visible in Settings

## Non-Goals

- Custom upgrade/downgrade UI (deferred -- no second tier exists)
- Discount-based retention offers (no churn data to calibrate)
- Invoice history display (separate issue #1079)
- Stripe live mode activation (Phase 4, #1444)
- Win-back email sequences (future marketing initiative)
- Subscription pause functionality

## Functional Requirements

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| FR1 | Stripe Customer Portal integration | `/api/billing/portal` route creates billing portal session and returns redirect URL. Portal allows cancel and payment method update. |
| FR2 | Pre-cancel interstitial page | Custom page displays: KB artifact count, conversation count, configured service count, time since signup. Two CTAs: "Keep my account" (primary), "Continue to cancel" (secondary, redirects to portal). |
| FR3 | Webhook: subscription.updated | Handle `customer.subscription.updated` events. Update `subscription_status`, `cancel_at_period_end`, `current_period_end`, `current_plan` on users table. Idempotent (check event timestamp or use Stripe event ID). |
| FR4 | Webhook: subscription.deleted | Existing handler. Verify it sets `subscription_status = 'cancelled'` and clears `cancel_at_period_end`. |
| FR5 | Grace period access | Full platform access while `current_period_end > now()` regardless of `cancel_at_period_end` status. No degraded state. |
| FR6 | Billing section in Settings | Show: current plan name, subscription status badge, billing period end date (if active), "Manage subscription" button (opens portal). Show cancel confirmation banner if `cancel_at_period_end = true`. |
| FR7 | Fix duplicate Stripe customers | Checkout route uses existing `stripe_customer_id` (if present) instead of `customer_email` to prevent duplicate Stripe customer creation. |

## Technical Requirements

| ID | Requirement | Details |
|----|-------------|---------|
| TR1 | Database migration | Add to users table: `stripe_subscription_id text`, `current_period_end timestamptz`, `cancel_at_period_end boolean default false`, `current_plan text`. |
| TR2 | RLS fix for billing columns | Table-level REVOKE UPDATE on users for authenticated role. Re-GRANT UPDATE only on non-billing columns (email, workspace_path, workspace_status, tc_accepted_at, etc.). Billing columns writable only via service role. |
| TR3 | CSRF exemption | Webhook route already exempt. New `/api/billing/portal` route requires CSRF validation (state-mutating, authenticated). |
| TR4 | Webhook idempotency | Store and check Stripe event IDs to prevent duplicate processing. Or use `created` timestamp comparison to reject stale events. |
| TR5 | Doppler configuration | Verify `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` in dev/prd/ci configs. Add `STRIPE_PORTAL_CONFIG_ID` if pinning portal configuration. No new secrets expected. |
| TR6 | Agent env isolation | Verify no new Stripe env vars leak to agent subprocess. Existing `buildAgentEnv()` allowlist should already exclude. Add test assertion. |
| TR7 | Async webhook processing | Keep webhook handler thin (return 200 quickly). If future logic grows (emails, provisioning), queue async work. Current scope is DB update only -- acceptable synchronous. |

## Test Scenarios

| Scenario | Expected Behavior |
|----------|-------------------|
| User clicks "Manage subscription" in Settings | Redirected to Stripe Customer Portal |
| User clicks "Cancel subscription" in portal | `subscription.updated` webhook fires with `cancel_at_period_end: true`. User sees cancellation banner in Settings. Full access continues. |
| Billing period ends after cancellation | `subscription.deleted` webhook fires. `subscription_status` set to `cancelled`. Access revoked on next auth check. |
| Duplicate webhook delivery | Second event processed idempotently (no state corruption) |
| User without subscription visits billing section | Shows "No active subscription" with subscribe CTA |
| Cancelled user with time remaining visits platform | Full access (agents, KB, conversations, services all work) |
| Malicious client tries to SET subscription_status | RLS blocks the UPDATE on billing columns |
| User checks out twice | Second checkout uses existing `stripe_customer_id`, no duplicate Stripe customer |

## Dependencies

- Pricing page (#656) -- closed, provides plan context
- Invoice history (#1079) -- sibling feature, separate scope
- Plan enforcement (#1162) -- Phase 4, independent
- Stripe live mode (#1444) -- Phase 4, independent

## Deferred Items

| Item | Reason | Revisit When |
|------|--------|--------------|
| Upgrade/downgrade UI | Single tier, pricing undecided | Pricing tiers committed (Phase 4+) |
| Custom cancel flow | Portal sufficient for 0-user stage | User feedback indicates portal is inadequate |
| Discount-based retention | No churn data to calibrate | 50+ active users with churn patterns |
| ToS upgrade/downgrade terms | Feature deferred | Upgrade/downgrade feature ships |
| Cancellation reason survey | Adds complexity, low data at 0 users | 20+ cancellations to analyze |
| Win-back email sequence | Marketing initiative, not engineering | Retention-strategist defines journey |
