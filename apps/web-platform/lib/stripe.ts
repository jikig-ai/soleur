import Stripe from "stripe";
import type { PlanTier } from "@/lib/types";
import { getPriceTier } from "@/lib/stripe-price-tier-map";

let _stripe: Stripe | null = null;

export function getStripe(): Stripe {
  if (!_stripe) {
    _stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
  }
  return _stripe;
}

/**
 * Cached per-user tier lookup for the cap-hit Stripe fallback (FR6). At 0
 * paying users with Stripe's 99.99% SLA, a circuit breaker / token bucket is
 * overkill — a plain 60s memo is sufficient. If cap-hit telemetry surfaces a
 * measurable false-deny rate, revisit (see plan Risks & Mitigations).
 */
interface TierMemoEntry {
  tier: PlanTier;
  status: string;
  at: number;
}

const TIER_MEMO_TTL_MS = 60_000;
const tierMemo = new Map<string, TierMemoEntry>();

/**
 * Fetch the user's plan tier directly from Stripe. Called on slot-acquire
 * cap-hit as a one-shot live check before denying the session, to cover the
 * webhook-lag window where a just-upgraded user still has the old plan_tier
 * in the DB. Callers should invoke `invalidateTierMemo(userId)` on any
 * `customer.subscription.*` webhook event (Phase 4).
 */
export async function retrieveSubscriptionTier(
  userId: string,
  subscriptionId: string,
): Promise<{ tier: PlanTier; status: string }> {
  const cached = tierMemo.get(userId);
  if (cached && Date.now() - cached.at < TIER_MEMO_TTL_MS) {
    return { tier: cached.tier, status: cached.status };
  }
  const sub = await getStripe().subscriptions.retrieve(subscriptionId);
  const firstItem = sub.items.data[0];
  const tier: PlanTier = firstItem?.price?.id
    ? getPriceTier(firstItem.price.id)
    : "free";
  const entry: TierMemoEntry = {
    tier,
    status: sub.status,
    at: Date.now(),
  };
  tierMemo.set(userId, entry);
  return { tier: entry.tier, status: entry.status };
}

/** Invalidate the per-user tier memo. Called by Stripe webhook handler
 *  for any customer.subscription.* event. */
export function invalidateTierMemo(userId: string): void {
  tierMemo.delete(userId);
}

/** Test-only: wipe the entire memo between tests. */
export function __resetTierMemoForTests(): void {
  tierMemo.clear();
}
