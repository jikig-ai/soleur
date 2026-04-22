import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getStripe } from "@/lib/stripe";
import { priceIdForTier } from "@/lib/stripe-price-tier-map";
import type { PlanTier } from "@/lib/types";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { APP_URL_FALLBACK, reportSilentFallback } from "@/server/observability";
import logger from "@/server/logger";

const VALID_TARGET_TIERS: PlanTier[] = ["solo", "startup", "scale", "enterprise"];

function isPlanTier(v: unknown): v is PlanTier {
  return typeof v === "string" && (VALID_TARGET_TIERS as string[]).includes(v);
}

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/checkout", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Optional body parsing — the upgrade-at-capacity modal sends
  // `{ targetTier: "startup" | "scale" | ... }`. Legacy callers without a
  // body fall back to the single STRIPE_PRICE_ID env var (deprecated).
  let targetTier: PlanTier | null = null;
  try {
    const body = (await request.json().catch(() => null)) as unknown;
    if (body && typeof body === "object") {
      const t = (body as { targetTier?: unknown }).targetTier;
      if (isPlanTier(t)) targetTier = t;
      else if (t != null) {
        return NextResponse.json({ error: "Invalid targetTier" }, { status: 400 });
      }
    }
  } catch {
    // No body is fine — fall through to legacy path.
  }

  // Check existing billing state to reuse Stripe customer and block double-subscribe
  const { data: userData } = await supabase
    .from("users")
    .select("stripe_customer_id, subscription_status")
    .eq("id", user.id)
    .single();

  if (userData?.subscription_status === "active" && !targetTier) {
    // Legacy callers without a target cannot "re-subscribe". Plan-switch
    // upgrades go through targetTier (which is allowed on active subs).
    return NextResponse.json(
      { error: "Already subscribed" },
      { status: 400 },
    );
  }

  const appUrl = process.env.NEXT_PUBLIC_APP_URL;
  if (!appUrl) {
    reportSilentFallback(null, {
      feature: "checkout",
      op: "create-session",
      message: `NEXT_PUBLIC_APP_URL unset; checkout origin fallback to ${APP_URL_FALLBACK}`,
      extra: { userId: user.id },
    });
  }
  const appOrigin = appUrl ?? APP_URL_FALLBACK;

  const resolvedPriceId = targetTier
    ? priceIdForTier(targetTier)
    : process.env.STRIPE_PRICE_ID;

  if (!resolvedPriceId) {
    if (!targetTier) {
      logger.warn(
        { userId: user.id },
        "Legacy checkout: STRIPE_PRICE_ID missing and no targetTier provided",
      );
    }
    return NextResponse.json(
      { error: "No price configured for tier" },
      { status: 400 },
    );
  }

  if (!targetTier) {
    // Surface a single deprecation log per request — we'll remove the
    // STRIPE_PRICE_ID fallback once the front-end is fully on targetTier.
    logger.warn(
      { userId: user.id },
      "Legacy checkout: STRIPE_PRICE_ID env-var path is deprecated; pass targetTier",
    );
  }

  // Embedded Checkout (ui_mode: "embedded") mounts inside the upgrade modal
  // via `@stripe/react-stripe-js`'s <EmbeddedCheckoutProvider>. The
  // return_url {CHECKOUT_SESSION_ID} placeholder is substituted by Stripe
  // after confirmation so /dashboard can reload with upgrade=complete &
  // session_id=... and force a WS reconnect to re-read plan_tier.
  const returnUrl =
    `${appOrigin}/dashboard?upgrade=complete&session_id={CHECKOUT_SESSION_ID}`;

  const session = await getStripe().checkout.sessions.create({
    ...(userData?.stripe_customer_id
      ? { customer: userData.stripe_customer_id }
      : { customer_email: user.email }),
    mode: "subscription",
    ui_mode: "embedded",
    line_items: [{ price: resolvedPriceId, quantity: 1 }],
    return_url: returnUrl,
    metadata: { supabase_user_id: user.id, target_tier: targetTier ?? "legacy" },
  });

  return NextResponse.json({
    clientSecret: session.client_secret,
    // Legacy hosted-page callers still read `url` — keep the field so old
    // clients don't break. `url` is null on embedded sessions.
    url: session.url,
  });
}
