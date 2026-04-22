import type { PlanTier } from "@/lib/types";

/**
 * Per-tier concurrent-conversation limits. A slot = one active conversation
 * (see 2026-04-19 brainstorm Amendment A). Fan-out across domain-leader
 * specialists inside a conversation still counts as a single slot.
 *
 * Scale and Enterprise share the same hard cap. Enterprise gets the same
 * default but is the only tier that can be raised past PLATFORM_HARD_CAP via
 * `users.concurrency_override` (raise-only; see effectiveCap).
 */
export const PLAN_LIMITS: Record<PlanTier, number> = {
  free: 1,
  solo: 2,
  startup: 5,
  scale: 50,
  enterprise: 50,
};

/** Absolute ceiling for non-enterprise tiers. Enterprise can exceed via
 *  concurrency_override. */
export const PLATFORM_HARD_CAP = 50;

const TIER_LADDER: PlanTier[] = ["free", "solo", "startup", "scale", "enterprise"];

/**
 * Resolve the active cap for a session. Raise-only: override only applies if
 * it is greater than the tier default — a lower override never demotes a paid
 * tier (e.g. misconfigured 0 on a Solo user still gets 2).
 */
export function effectiveCap(
  tier: PlanTier | undefined,
  override: number | null | undefined,
): number {
  const base = tier ? PLAN_LIMITS[tier] : PLAN_LIMITS.free;
  if (override != null && override > base) return override;
  return base;
}

/** Next tier on the ladder, or null at the top. */
export function nextTier(tier: PlanTier): PlanTier | null {
  const i = TIER_LADDER.indexOf(tier);
  if (i < 0 || i >= TIER_LADDER.length - 1) return null;
  return TIER_LADDER[i + 1];
}
