import { NextResponse } from "next/server";
import { getStripe } from "@/lib/stripe";
import { createServiceClient } from "@/lib/supabase/server";
import type Stripe from "stripe";
import logger from "@/server/logger";

// Map Stripe subscription statuses to the CHECK constraint values.
// Stripe sends: active, canceled, incomplete, incomplete_expired, past_due, trialing, unpaid, paused.
// DB allows: none, active, cancelled, past_due, unpaid (migration 022).
function mapStripeStatus(stripeStatus: string): string {
  switch (stripeStatus) {
    case "active":
    case "trialing":
      return "active";
    case "past_due":
      return "past_due";
    case "unpaid":
      return "unpaid";
    case "canceled":
    case "incomplete_expired":
    case "paused":
      return "cancelled";
    default:
      return "active";
  }
}

function extractCustomerId(subscription: Stripe.Subscription): string {
  return typeof subscription.customer === "string"
    ? subscription.customer
    : subscription.customer.id;
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
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  const supabase = createServiceClient();

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as Stripe.Checkout.Session;
      const userId = session.metadata?.supabase_user_id;

      if (userId) {
        const { error } = await supabase
          .from("users")
          .update({
            stripe_customer_id: session.customer as string,
            subscription_status: "active",
            stripe_subscription_id: session.subscription as string,
          })
          .eq("id", userId);

        if (error) {
          logger.error({ error, userId }, "Webhook: failed to update user on checkout.session.completed");
          return NextResponse.json({ error: "DB update failed" }, { status: 500 });
        }
      }
      break;
    }

    case "customer.subscription.updated": {
      const subscription = event.data.object as Stripe.Subscription;
      const customerId = extractCustomerId(subscription);

      const { error } = await supabase
        .from("users")
        .update({
          subscription_status: mapStripeStatus(subscription.status),
          cancel_at_period_end: subscription.cancel_at_period_end,
          current_period_end: new Date(
            subscription.current_period_end * 1_000,
          ).toISOString(),
        })
        .eq("stripe_customer_id", customerId);

      if (error) {
        logger.error({ error, customerId }, "Webhook: failed to update user on customer.subscription.updated");
        return NextResponse.json({ error: "DB update failed" }, { status: 500 });
      }
      break;
    }

    case "customer.subscription.deleted": {
      const subscription = event.data.object as Stripe.Subscription;
      const customerId = extractCustomerId(subscription);

      const { error } = await supabase
        .from("users")
        .update({
          subscription_status: "cancelled",
          cancel_at_period_end: false,
          current_period_end: null,
        })
        .eq("stripe_customer_id", customerId);

      if (error) {
        logger.error({ error, customerId }, "Webhook: failed to update user on customer.subscription.deleted");
        return NextResponse.json({ error: "DB update failed" }, { status: 500 });
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
