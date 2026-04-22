import { NextResponse } from "next/server";
import { getStripe } from "@/lib/stripe";
import { getPriceTier } from "@/lib/stripe-price-tier-map";
import { effectiveCap } from "@/lib/plan-limits";
import type { PlanTier } from "@/lib/types";
import { onTierTransitionApplied } from "@/lib/stripe-subscription-transition";
import { createServiceClient } from "@/lib/supabase/server";
import {
  SUBSCRIPTION_LIVE_STATUSES,
  SUBSCRIPTION_UPDATABLE_STATUSES,
} from "@/lib/stripe-subscription-statuses";
import { PG_UNIQUE_VIOLATION } from "@/lib/postgres-errors";
import type Stripe from "stripe";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

// Map Stripe subscription statuses to the CHECK constraint values.
// Stripe sends: active, canceled, incomplete, incomplete_expired, past_due, trialing, unpaid, paused.
// DB allows: none, active, cancelled, past_due, unpaid (migration 022).
function mapStripeStatus(stripeStatus: Stripe.Subscription.Status): string {
  switch (stripeStatus) {
    case "active":
    case "trialing":
      return "active";
    case "past_due":
      return "past_due";
    case "unpaid":
      return "unpaid";
    case "canceled":
    case "incomplete":
    case "incomplete_expired":
    case "paused":
      return "cancelled";
    default: {
      const _exhaustive: never = stripeStatus;
      logger.warn({ stripeStatus: _exhaustive }, "Unknown Stripe subscription status — defaulting to 'cancelled' for safety");
      Sentry.captureMessage(`Unknown Stripe status: ${String(_exhaustive)}`, "warning");
      return "cancelled";
    }
  }
}

/**
 * Returns the customer id, or null for Stripe.DeletedCustomer objects.
 * A deleted customer cannot own a live subscription mutation — callers
 * should early-return and log rather than match rows by a stale id.
 */
function extractCustomerId(subscription: Stripe.Subscription): string | null {
  const c = subscription.customer;
  if (typeof c === "string") return c;
  if ("deleted" in c && c.deleted === true) return null;
  return c.id;
}

function deriveTierFromSubscription(
  subscription: Stripe.Subscription,
): PlanTier | null {
  // Tests and partial-fixture replays may omit items.data entirely. In that
  // case we cannot compute a tier and the handler should leave plan_tier
  // untouched rather than fall through to "free" (which would silently
  // downgrade a real user on a malformed replay).
  const firstItem = subscription.items?.data?.[0];
  const priceId = firstItem?.price?.id;
  if (!priceId) return null;
  return getPriceTier(priceId);
}

export async function POST(request: Request) {
  const body = await request.text();
  const signature = request.headers.get("stripe-signature");

  if (!signature) {
    return NextResponse.json(
      { error: "Missing stripe-signature header" },
      { status: 400 },
    );
  }

  let event: Stripe.Event;
  try {
    event = getStripe().webhooks.constructEvent(
      body,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET!,
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    logger.error({ err: message }, "Stripe webhook signature verification failed");
    // Security-relevant: a spike in signature failures is an attack signal.
    // captureMessage (not captureException) — the original err may be a
    // thrown string and we already reduced it to a sanitized message.
    Sentry.captureMessage("Stripe webhook signature verification failed", {
      level: "error",
      tags: { feature: "stripe-webhook", op: "signature" },
      extra: { message },
    });
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  const supabase = createServiceClient();

  // Webhook-event-id dedup gate (#2772). Stripe delivers at-least-once; a
  // replay of an already-processed event short-circuits here with 200.
  // Critical: on handler error below we DELETE this row via
  // releaseDedupRow() before returning 5xx so Stripe's retry re-enters.
  // Service-role bypasses RLS; the table has no policies.
  //
  // Accepted tradeoff: if the Node process crashes between this INSERT
  // commit and a handler 5xx (rare at Vercel function scale — timeouts
  // fire at 10-60s, handler p99 is sub-second), the row is orphaned and
  // Stripe's retry 23505-short-circuits. The event is operator-replayable
  // from the Stripe dashboard; a deeper fix (TTL-reclaim or SECURITY
  // DEFINER RPC transaction) is tracked as a follow-up.
  const { error: dedupErr } = await supabase
    .from("processed_stripe_events")
    .insert({ event_id: event.id, event_type: event.type });

  if (dedupErr) {
    if (dedupErr.code === PG_UNIQUE_VIOLATION) {
      logger.info(
        { eventId: event.id, eventType: event.type },
        "Stripe webhook replay — event already processed, skipping",
      );
      return NextResponse.json({ received: true });
    }
    logger.error(
      { err: dedupErr, eventId: event.id },
      "Stripe webhook dedup insert failed — returning 500",
    );
    Sentry.captureException(dedupErr, {
      tags: { feature: "stripe-webhook", op: "dedup-insert" },
      extra: { eventId: event.id, eventType: event.type },
    });
    return NextResponse.json({ error: "DB error" }, { status: 500 });
  }

  // On any 5xx error path below, call this before returning so Stripe's
  // retry re-enters cleanly. Silently tolerates a DELETE failure — the
  // Stripe retry is the correction mechanism, and per-handler .in() guards
  // block double-apply if DELETE fails and retry short-circuits.
  async function releaseDedupRow(): Promise<void> {
    const { error } = await supabase
      .from("processed_stripe_events")
      .delete()
      .eq("event_id", event.id);
    if (error) {
      logger.error(
        { err: error, eventId: event.id },
        "Stripe webhook: failed to release dedup row on handler error — retry will be short-circuited",
      );
      Sentry.captureException(error, {
        tags: { feature: "stripe-webhook", op: "dedup-release" },
        extra: { eventId: event.id },
      });
    }
  }

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as Stripe.Checkout.Session;
      const userId = session.metadata?.supabase_user_id;

      if (userId) {
        // Guard: never resurrect a cancelled row via a replayed checkout
        // event (#2771). The dedup table above closes this today, but the
        // guard is kept as belt-and-suspenders for the release-on-error
        // window and for environments before migration 030 is applied.
        const { data, error } = await supabase
          .from("users")
          .update({
            stripe_customer_id: session.customer as string,
            subscription_status: "active",
            stripe_subscription_id: session.subscription as string,
          })
          .eq("id", userId)
          .in("subscription_status", SUBSCRIPTION_UPDATABLE_STATUSES)
          .select("id");

        if (error) {
          logger.error({ error, userId }, "Webhook: failed to update user on checkout.session.completed");
          Sentry.captureException(error, {
            tags: { feature: "stripe-webhook", op: "checkout.session.completed" },
            extra: { userId },
          });
          await releaseDedupRow();
          return NextResponse.json({ error: "DB update failed" }, { status: 500 });
        }

        const matched = data?.length ?? 0;
        if (matched === 0) {
          logger.warn(
            { userId, eventId: event.id },
            "Webhook: checkout.session.completed guard no-op — row not in updatable status (likely cancelled or replay after dedup-row released)",
          );
        }
      }
      break;
    }

    case "customer.subscription.updated": {
      const subscription = event.data.object as Stripe.Subscription;
      const customerId = extractCustomerId(subscription);
      if (!customerId) {
        logger.warn(
          { subId: subscription.id, eventId: event.id },
          "Webhook: subscription.updated on deleted customer — skipping",
        );
        break;
      }
      const newStatus = mapStripeStatus(subscription.status);

      // Stripe `incomplete` status: the subscription is pending SCA or
      // initial payment confirmation. Do NOT grant plan_tier here —
      // checkout.session.completed (or a later customer.subscription.updated
      // with status=active) is the grant trigger. V1 ships without a
      // dedicated UpgradePendingBanner; client shows a generic error.
      if (subscription.status === "incomplete") {
        logger.info(
          { customerId, subId: subscription.id },
          "Stripe subscription incomplete — skipping plan_tier grant",
        );
        break;
      }

      // Look up the current row so we can compute whether this is an
      // upgrade, downgrade, or idempotent replay.
      const { data: currentRow, error: selErr } = await supabase
        .from("users")
        .select("id, plan_tier, concurrency_override, subscription_downgraded_at, subscription_status")
        .eq("stripe_customer_id", customerId)
        .maybeSingle();

      if (selErr) {
        Sentry.captureException(selErr, {
          tags: { feature: "stripe-webhook", op: "customer.subscription.updated" },
          extra: { customerId },
        });
        await releaseDedupRow();
        return NextResponse.json({ error: "DB lookup failed" }, { status: 500 });
      }
      if (!currentRow) {
        logger.warn({ customerId }, "No user row for Stripe customer — skipping");
        break;
      }

      const currentTier = (currentRow as { plan_tier?: PlanTier | null }).plan_tier ?? "free";
      const currentOverride = (currentRow as { concurrency_override?: number | null }).concurrency_override ?? null;
      const userId = (currentRow as { id: string }).id;
      const derivedTier = deriveTierFromSubscription(subscription);
      // If the event had no items to derive a price from, keep the current
      // tier so a malformed replay does not silently downgrade.
      const newTier = derivedTier ?? currentTier;

      const currentCap = effectiveCap(currentTier, currentOverride);
      const newCap = effectiveCap(newTier, currentOverride);
      const isDowngrade = newCap < currentCap;
      const isUpgrade = newCap > currentCap;

      const updatePatch: Record<string, unknown> = {
        subscription_status: newStatus,
        cancel_at_period_end: subscription.cancel_at_period_end,
        current_period_end: new Date(
          subscription.current_period_end * 1_000,
        ).toISOString(),
      };
      if (derivedTier !== null) {
        updatePatch.plan_tier = derivedTier;
      }
      if (isDowngrade) {
        updatePatch.subscription_downgraded_at = new Date(
          event.created * 1_000,
        ).toISOString();
      } else if (isUpgrade) {
        updatePatch.subscription_downgraded_at = null;
      }

      // Never resurrect a cancelled row: a stale .updated delivered out-of-order
      // after .deleted must be a no-op regardless of newStatus. Resurrection to
      // "past_due" or "unpaid" is just as wrong as resurrection to "active"
      // (re-enables billing-side features the user no longer pays for).
      // SUBSCRIPTION_UPDATABLE_STATUSES explicitly excludes "cancelled" —
      // cancelled is terminal; see #2701.
      const { data, error } = await supabase
        .from("users")
        .update(updatePatch)
        .eq("stripe_customer_id", customerId)
        .in("subscription_status", SUBSCRIPTION_UPDATABLE_STATUSES)
        .select("id");

      if (error) {
        logger.error({ error, customerId }, "Webhook: failed to update user on customer.subscription.updated");
        Sentry.captureException(error, {
          tags: { feature: "stripe-webhook", op: "customer.subscription.updated" },
          extra: { customerId },
        });
        await releaseDedupRow();
        return NextResponse.json({ error: "DB update failed" }, { status: 500 });
      }

      const matched = data?.length ?? 0;
      if (matched === 0) {
        // Guard fired (row is cancelled, or no row exists for this customer).
        // Promoted to warn so ops can detect stale-event noise vs. real
        // missing-row issues.
        logger.warn(
          { customerId, eventId: event.id, newStatus },
          "Webhook: customer.subscription.updated guard no-op — row not in updatable status",
        );
      } else {
        logger.info(
          { customerId, eventId: event.id, matched, newStatus },
          "Webhook: customer.subscription.updated applied",
        );
        onTierTransitionApplied({
          userId,
          previousTier: currentTier,
          newTier,
          concurrencyOverride: currentOverride,
        });
      }
      break;
    }

    case "customer.subscription.deleted": {
      const subscription = event.data.object as Stripe.Subscription;
      const customerId = extractCustomerId(subscription);
      if (!customerId) {
        logger.warn(
          { subId: subscription.id, eventId: event.id },
          "Webhook: subscription.deleted on deleted customer — skipping",
        );
        break;
      }

      const { data: currentRow, error: selErr } = await supabase
        .from("users")
        .select("id, plan_tier, concurrency_override")
        .eq("stripe_customer_id", customerId)
        .maybeSingle();

      if (selErr) {
        Sentry.captureException(selErr, {
          tags: { feature: "stripe-webhook", op: "customer.subscription.deleted" },
          extra: { customerId },
        });
        await releaseDedupRow();
        return NextResponse.json({ error: "DB lookup failed" }, { status: 500 });
      }

      const userId = (currentRow as { id: string } | null)?.id;
      const previousTier =
        (currentRow as { plan_tier?: PlanTier | null } | null)?.plan_tier ?? "free";
      const currentOverride =
        (currentRow as { concurrency_override?: number | null } | null)?.concurrency_override ?? null;

      // Only cancel if currently active/past_due/unpaid; a stale deleted event
      // delivered after an already-cancelled row must be a no-op. "none"
      // (never subscribed) is excluded — a real .deleted cannot fire against
      // a never-subscribed customer. Folds #2190.
      const { data, error } = await supabase
        .from("users")
        .update({
          plan_tier: "free",
          subscription_status: "cancelled",
          cancel_at_period_end: false,
          current_period_end: null,
          subscription_downgraded_at: new Date((event.created ?? Math.floor(Date.now() / 1_000)) * 1_000).toISOString(),
        })
        .eq("stripe_customer_id", customerId)
        .in("subscription_status", SUBSCRIPTION_LIVE_STATUSES)
        .select("id");

      if (error) {
        logger.error({ error, customerId }, "Webhook: failed to update user on customer.subscription.deleted");
        Sentry.captureException(error, {
          tags: { feature: "stripe-webhook", op: "customer.subscription.deleted" },
          extra: { customerId },
        });
        await releaseDedupRow();
        return NextResponse.json({ error: "DB update failed" }, { status: 500 });
      }

      const matched = data?.length ?? 0;
      if (matched === 0) {
        logger.warn(
          { customerId, eventId: event.id },
          "Webhook: customer.subscription.deleted guard no-op — row already cancelled or not found",
        );
      } else {
        logger.info(
          { customerId, eventId: event.id, matched },
          "Webhook: customer.subscription.deleted applied",
        );
        if (userId) {
          onTierTransitionApplied({
            userId,
            previousTier,
            newTier: "free",
            concurrencyOverride: currentOverride,
          });
        }
      }
      break;
    }

    case "invoice.payment_failed": {
      const invoice = event.data.object as Stripe.Invoice;
      const customerId =
        typeof invoice.customer === "string"
          ? invoice.customer
          : invoice.customer?.id;
      logger.warn(
        { customerId, invoiceId: invoice.id },
        "Stripe invoice.payment_failed — logged for observability, status managed by customer.subscription.updated",
      );
      break;
    }

    case "invoice.paid": {
      const invoice = event.data.object as Stripe.Invoice;
      const customerId =
        typeof invoice.customer === "string"
          ? invoice.customer
          : invoice.customer?.id;

      if (customerId) {
        // Only restore active if currently past_due or unpaid.
        // customer.subscription.updated is the source of truth for active
        // transitions; this is a belt-and-suspenders restore that must not
        // reactivate cancelled subs (idempotent against Stripe replays).
        const { data, error } = await supabase
          .from("users")
          .update({ subscription_status: "active" })
          .eq("stripe_customer_id", customerId)
          .in("subscription_status", ["past_due", "unpaid"])
          .select("id");

        if (error) {
          logger.error(
            { error, customerId },
            "Webhook: failed to update user on invoice.paid",
          );
          Sentry.captureException(error, {
            tags: { feature: "stripe-webhook", op: "invoice.paid" },
            extra: { customerId },
          });
          await releaseDedupRow();
          return NextResponse.json(
            { error: "DB update failed" },
            { status: 500 },
          );
        }

        logger.info(
          { customerId, matched: data?.length ?? 0, invoiceId: invoice.id },
          "Webhook: invoice.paid applied",
        );
      }
      break;
    }

    default:
      // Unhandled event type — acknowledge receipt
      break;
  }

  return NextResponse.json({ received: true });
}
