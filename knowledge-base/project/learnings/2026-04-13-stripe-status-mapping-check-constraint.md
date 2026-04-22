---
title: Stripe subscription status must be mapped to DB CHECK constraint values
date: 2026-04-13
category: integration-issues
tags: [stripe, webhooks, supabase, check-constraint]
symptoms: webhook returns 200 but DB update silently fails
module: apps/web-platform/app/api/webhooks/stripe
---

# Stripe subscription status must be mapped to DB CHECK constraint values

## Problem

The `customer.subscription.updated` webhook handler wrote `subscription.status`
directly from Stripe into the `subscription_status` column. The column has a
CHECK constraint (migration 002) allowing only `none`, `active`, `cancelled`,
`past_due`. Stripe sends additional statuses: `incomplete`, `incomplete_expired`,
`trialing`, `unpaid`, `paused`, `canceled` (American spelling).

The webhook handler also did not check `{ error }` from the Supabase update call,
so it returned `{ received: true }` with status 200. Stripe marked the webhook as
delivered and never retried. The user's subscription state silently diverged from
Stripe.

## Solution

1. Added `mapStripeStatus()` function that maps all Stripe statuses to the four
   allowed DB values (trialing→active, unpaid→past_due, canceled→cancelled, etc.)
2. Added error checking to all three webhook handlers — return 500 on DB failure
   so Stripe retries
3. Extracted `extractCustomerId()` helper to deduplicate the string-or-object check

## Key Insight

When writing webhook handlers that store external service state in a constrained
DB column, always map the external values to the local enum — never pass through
raw values. The webhook handler must also check DB write results and return a
non-200 status on failure, otherwise the external service marks the event as
delivered and the failure is unrecoverable without manual intervention.

## Session Errors

1. **npx vitest used wrong global version** — Recovery: switched to local
   `./node_modules/.bin/vitest`. Prevention: always use project-local binary
   for test runners.
2. **Obsolete test broke after page replacement** — Recovery: removed
   `billing-cost-list.test.tsx`. Prevention: when replacing a component with a
   redirect, check for tests that import the old component.
3. **Missing import in test file** — Recovery: added `afterEach` to imports.
   Prevention: verify test file compiles before committing.
4. **git add from wrong directory** — Recovery: cd to worktree root.
   Prevention: use absolute paths or verify CWD before git commands.

## See Also

- `knowledge-base/project/learnings/integration-issues/2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern.md` —
  Followup layer: `processed_stripe_events` dedup table + checkout out-of-order
  guard. Extends this learning's mapping + error-check discipline with a
  replay-blocking gate.

## Tags

category: integration-issues
module: apps/web-platform/app/api/webhooks/stripe
