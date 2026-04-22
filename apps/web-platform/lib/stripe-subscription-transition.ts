import type { PlanTier } from "@/lib/types";
import { effectiveCap } from "@/lib/plan-limits";
import { invalidateTierMemo } from "@/lib/stripe";
import { forceDisconnectForTierChange } from "@/server/ws-handler";

/**
 * Side effects that run AFTER a tier transition has been atomically applied
 * to the users row (matched > 0). Keeps the two webhook branches
 * (customer.subscription.updated, customer.subscription.deleted) honest by
 * collapsing their shared pattern:
 *
 *   1. Invalidate the per-user tier memo so the cap-hit Stripe fallback
 *      does not serve a stale cached value.
 *   2. On a cap-reducing transition, force-disconnect any live WS session
 *      so the client reconnects and lands on the new cap.
 *
 * Not called on guard-no-op (matched == 0). If the atomic update did not
 * commit, the memo / WS state remain authoritative for the prior state.
 */
export function onTierTransitionApplied(args: {
  userId: string;
  previousTier: PlanTier;
  newTier: PlanTier;
  concurrencyOverride: number | null;
}): void {
  const { userId, previousTier, newTier, concurrencyOverride } = args;
  invalidateTierMemo(userId);
  const prevCap = effectiveCap(previousTier, concurrencyOverride);
  const newCap = effectiveCap(newTier, concurrencyOverride);
  if (newCap < prevCap) {
    forceDisconnectForTierChange(userId, {
      type: "tier_changed",
      previousTier,
      newTier,
    });
  }
}
