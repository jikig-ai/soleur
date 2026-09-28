import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { getStripe } from "@/lib/stripe";
import { priceIdForTier } from "@/lib/stripe-price-tier-map";
import type { PlanTier } from "@/lib/types";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { PG_UNIQUE_VIOLATION, sqlStateFromError } from "@/lib/postgres-errors";
import { APP_URL_FALLBACK, reportSilentFallback } from "@/server/observability";
import * as Sentry from "@sentry/nextjs";
import logger from "@/server/logger";

const VALID_TARGET_TIERS: PlanTier[] = ["solo", "startup", "scale", "enterprise"];

// #8918 — a marker with no session_id means a sibling request won the claim
// and is mid-sessions.create; a marker older than this is crashed-claim
// residue and reclaimable.
const STALE_NULL_MARKER_MS = 60_000;
// One claim + one retry after a reclaim. The PK arbitrates any residual
// interleaving — a loser re-enters the marker-hit path rather than failing.
const MAX_CLAIM_ATTEMPTS = 2;

function isPlanTier(v: unknown): v is PlanTier {
  return typeof v === "string" && (VALID_TARGET_TIERS as string[]).includes(v);
}

function checkoutInProgress() {
  return NextResponse.json(
    {
      error: "Checkout is already starting — please wait a moment.",
      code: "checkout_in_progress",
    },
    { status: 409 },
  );
}

function checkoutError(err: unknown, op: string, extra: Record<string, unknown>) {
  logger.error({ err, op, ...extra }, `checkout ${op} failed`);
  Sentry.captureException(err, {
    tags: { feature: "checkout", op },
    extra,
  });
  return NextResponse.json({ error: "Checkout unavailable" }, { status: 500 });
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

  // #8918 — server-side idempotency. The pending_checkout_sessions PK on
  // user_id is the only serialization point that survives Vercel's
  // per-invocation concurrency: claim via INSERT, and a 23505 routes the
  // loser into the marker-hit path below. All 4xx exits above deliberately
  // run BEFORE the claim so error paths never hold a slot.
  const resolvedTier = targetTier ?? "legacy";
  const service = createServiceClient();
  const stripe = getStripe();

  for (let attempt = 0; attempt < MAX_CLAIM_ATTEMPTS; attempt++) {
    const { error: claimErr } = await service
      .from("pending_checkout_sessions")
      .insert({ user_id: user.id, target_tier: resolvedTier });

    if (!claimErr) {
      // Own the slot — create, record, return.
      try {
        const session = await stripe.checkout.sessions.create(
          {
            ...(userData?.stripe_customer_id
              ? { customer: userData.stripe_customer_id }
              : { customer_email: user.email }),
            mode: "subscription",
            ui_mode: "embedded",
            line_items: [{ price: resolvedPriceId, quantity: 1 }],
            return_url: returnUrl,
            metadata: {
              supabase_user_id: user.id,
              target_tier: resolvedTier,
            },
          },
          // Fresh UUID per attempt — belt for SDK-level retries. Never a
          // deterministic user+tier key: Stripe replays the cached first
          // response within key retention (stale/completed sessions).
          { idempotencyKey: randomUUID() },
        );

        // Record the session so a racing marker-hit can retrieve it. A
        // failed UPDATE is logged but not fatal — the marker's null
        // session_id reclaims itself via the staleness path.
        const { error: updateErr } = await service
          .from("pending_checkout_sessions")
          .update({ session_id: session.id })
          .eq("user_id", user.id);
        if (updateErr) {
          logger.warn(
            { err: updateErr, userId: user.id },
            "checkout: marker session_id update failed — marker self-heals via stale-null reclaim",
          );
        }

        return NextResponse.json({
          clientSecret: session.client_secret,
          // Legacy hosted-page callers still read `url` — keep the field so
          // old clients don't break. `url` is null on embedded sessions.
          url: session.url,
        });
      } catch (err) {
        // Release the marker before the 5xx so a retry re-enters cleanly
        // (mirrors releaseDedupRow() in the webhook route).
        await service
          .from("pending_checkout_sessions")
          .delete()
          .eq("user_id", user.id);
        return checkoutError(err, "create-session", { userId: user.id });
      }
    }

    if (sqlStateFromError(claimErr) !== PG_UNIQUE_VIOLATION) {
      return checkoutError(claimErr, "claim-insert", { userId: user.id });
    }

    // Marker-hit: a sibling request owns a claim. Retrieve the marker row.
    const { data: marker, error: markerErr } = await service
      .from("pending_checkout_sessions")
      .select("session_id, target_tier, created_at")
      .eq("user_id", user.id)
      .maybeSingle();

    if (markerErr) {
      return checkoutError(markerErr, "marker-select", { userId: user.id });
    }
    if (!marker) {
      // The marker vanished between the 23505 and our SELECT (sibling
      // reclaimed/completed) — retry the claim.
      continue;
    }

    if (marker.session_id) {
      let existing;
      try {
        existing = await stripe.checkout.sessions.retrieve(marker.session_id);
      } catch (err) {
        // Fail-closed: reclaiming on a transient Stripe outage would let a
        // second session coexist with the open first — the exact defect
        // this table exists to close. Marker is left untouched.
        return checkoutError(err, "session-retrieve", { userId: user.id });
      }

      if (existing.status === "open" && marker.target_tier === resolvedTier) {
        if (existing.client_secret) {
          // Join the sibling's session instead of erroring — the second
          // POST gets the same client_secret back.
          return NextResponse.json({
            clientSecret: existing.client_secret,
            url: existing.url,
          });
        }
        // Open but no client_secret — do not reclaim a session Stripe
        // reports open.
        return checkoutInProgress();
      }

      if (existing.status === "open") {
        // Different tier: a wrong-price reuse is worse than no reuse —
        // expire the stale session before reclaiming the marker.
        try {
          await stripe.checkout.sessions.expire(marker.session_id);
        } catch (err) {
          return checkoutError(err, "session-expire", { userId: user.id });
        }
      }

      // complete / expired / just-expired-by-us — reclaim the marker and
      // retry the claim once.
      logger.warn(
        { userId: user.id, sessionId: marker.session_id, status: existing.status },
        "checkout: reclaiming completed/expired marker",
      );
      await service
        .from("pending_checkout_sessions")
        .delete()
        .eq("user_id", user.id);
      continue;
    }

    // Marker has no session_id yet — sibling is mid-sessions.create.
    const markerAgeMs = Date.now() - new Date(marker.created_at).getTime();
    if (markerAgeMs < STALE_NULL_MARKER_MS) {
      return checkoutInProgress();
    }

    // Crashed-claim residue — reclaim and retry once.
    logger.warn(
      { userId: user.id, markerAgeMs },
      "checkout: reclaiming stale null-session marker",
    );
    await service
      .from("pending_checkout_sessions")
      .delete()
      .eq("user_id", user.id);
  }

  // Claim + one reclaim both lost to a sibling — surface the same
  // in-progress signal rather than loop forever.
  return checkoutInProgress();
}
