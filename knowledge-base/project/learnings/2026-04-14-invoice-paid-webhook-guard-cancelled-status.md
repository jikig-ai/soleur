---
name: invoice.paid webhook guard — cancelled subscription protection
description: How to guard a Stripe invoice.paid handler to prevent reactivating cancelled subscriptions
type: project
---

# Learning: invoice.paid webhook guard — cancelled subscription protection

## Problem

The `invoice.paid` webhook handler in `apps/web-platform/app/api/webhooks/stripe/route.ts` unconditionally set `subscription_status = 'active'` for any paying customer:

```typescript
case "invoice.paid": {
  // ...
  const { error } = await supabase
    .from("users")
    .update({ subscription_status: "active" })
    .eq("stripe_customer_id", customerId);
  // ...
}
```

Stripe fires `invoice.paid` for final invoices on cancelled subscriptions (e.g., the last billing cycle closes out with a payment). This meant a cancelled subscription could be silently reactivated in the DB — the user would regain access they were no longer entitled to with no visibility into why.

The root cause is that `invoice.paid` is not a signal that the subscription is currently active; it only means a specific invoice was settled. The subscription state is authoritative only on `customer.subscription.updated` and `customer.subscription.deleted` events.

## Solution

Fetch the current `subscription_status` from the DB before updating. Only advance to `'active'` if the current status is a recoverable delinquent state (`'past_due'` or `'unpaid'`). Skip the update entirely for any other status (including `'cancelled'`).

```typescript
case "invoice.paid": {
  const invoice = event.data.object as Stripe.Invoice;
  const customerId =
    typeof invoice.customer === "string"
      ? invoice.customer
      : invoice.customer?.id;

  if (customerId) {
    // Fetch current status before updating — only restore from delinquent states.
    // invoice.paid fires on cancelled subscriptions too; blindly setting 'active'
    // would silently reactivate a cancelled account.
    const { data: userRow, error: fetchError } = await supabase
      .from("users")
      .select("subscription_status")
      .eq("stripe_customer_id", customerId)
      .single();

    if (fetchError) {
      logger.error(
        { error: fetchError, customerId },
        "Webhook: failed to fetch user status on invoice.paid",
      );
      return NextResponse.json({ error: "DB fetch failed" }, { status: 500 });
    }

    const recoverableStatuses = ["past_due", "unpaid"];
    if (userRow && recoverableStatuses.includes(userRow.subscription_status)) {
      const { error } = await supabase
        .from("users")
        .update({ subscription_status: "active" })
        .eq("stripe_customer_id", customerId);

      if (error) {
        logger.error(
          { error, customerId },
          "Webhook: failed to update user on invoice.paid",
        );
        return NextResponse.json({ error: "DB update failed" }, { status: 500 });
      }
    } else {
      logger.info(
        { customerId, currentStatus: userRow?.subscription_status },
        "Webhook: invoice.paid skipped status update — not in recoverable state",
      );
    }
  }
  break;
}
```

## Key Insight

`invoice.paid` means "money was collected for this invoice", not "this subscription is now active". Stripe's event hierarchy for subscription lifecycle is:

- **State transitions** — `customer.subscription.updated`, `customer.subscription.deleted`
- **Payment notifications** — `invoice.paid`, `invoice.payment_failed`

Payment notifications should only act on status if transitioning from a known delinquent state. Any unconditional write to `subscription_status` in a payment event handler is a potential correctness bug.

**General pattern:** When a webhook event does not solely represent a state transition, always read before writing. Gate writes on the current DB state, not the event type alone.

## Session Errors

1. **`worktree-manager.sh --yes create` exited 128** — The script's `git fetch origin main:main` step fails on CI runners where the bare repo does not allow local ref updates via fast-forward fetch syntax.
   - Recovery: Manually ran `git branch <name> main && git worktree add .worktrees/<name> <name>`.
   - Prevention: `worktree-manager.sh` should detect a non-zero exit from `git fetch origin main:main` and fall back to `git branch <name> $(git rev-parse main) && git worktree add .worktrees/<name> <name>`.

2. **`node node_modules/vitest/vitest.mjs` failed — deps not installed** — On this CI runner, `apps/web-platform/node_modules` was absent. No test baseline could be established.
   - Recovery: Proceeded without a local test run; relied on CI.
   - Prevention: Add a pre-session check: `[ -d apps/web-platform/node_modules ] || (cd apps/web-platform && npm install)` before running vitest. Document this as a required setup step in the worktree creation script.

## Tags

category: logic-errors
module: apps/web-platform/app/api/webhooks/stripe/route.ts
tags: [stripe, webhooks, billing, subscription, cancelled, invoice.paid, guard, idempotency]
