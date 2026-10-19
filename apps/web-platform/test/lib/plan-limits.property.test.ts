import { describe, expect, it } from "vitest";
import fc from "fast-check";
import {
  effectiveCap,
  nextTier,
  PLAN_LIMITS,
  PLATFORM_HARD_CAP,
} from "@/lib/plan-limits";
import type { PlanTier } from "@/lib/types";

// Property-based suite (fast-check) — invariant class over the plan-tier
// limit helpers. Convention: on failure, shrink and pin the counterexample
// as a permanent it() labelled
// `// regression fixture: fast-check seed <seed> path <path>`.
// See apps/web-platform/test/README.md "Property-based tests".

const tierArb = fc.constantFrom<PlanTier>(
  "free",
  "solo",
  "startup",
  "scale",
  "enterprise",
);
const maybeTierArb = fc.oneof(tierArb, fc.constant(undefined));
// override: null | undefined | arbitrary integer (negative, 0, huge).
const overrideArb = fc.oneof(
  fc.constant(null),
  fc.constant(undefined),
  fc.integer({ min: -100, max: 200 }),
  fc.integer(),
);

const baseOf = (tier: PlanTier | undefined): number =>
  tier ? PLAN_LIMITS[tier] : PLAN_LIMITS.free;

describe("plan-limits — effectiveCap invariants (property)", () => {
  it("result is always the tier base or the override — never a third value", () => {
    fc.assert(
      fc.property(maybeTierArb, overrideArb, (tier, override) => {
        const base = baseOf(tier);
        const cap = effectiveCap(tier, override);
        expect(cap === base || cap === override).toBe(true);
      }),
    );
  });

  it("raise-only: the cap never demotes below the tier base", () => {
    fc.assert(
      fc.property(maybeTierArb, overrideArb, (tier, override) => {
        const base = baseOf(tier);
        const cap = effectiveCap(tier, override);
        expect(cap).toBeGreaterThanOrEqual(base);
        // Full contract: override applies iff it strictly exceeds base.
        if (override != null && override > base) {
          expect(cap).toBe(override);
        } else {
          expect(cap).toBe(base);
        }
      }),
    );
  });

  it("monotone non-decreasing in override", () => {
    fc.assert(
      fc.property(maybeTierArb, fc.integer(), fc.integer(), (tier, a, b) => {
        const [lo, hi] = a <= b ? [a, b] : [b, a];
        expect(effectiveCap(tier, lo)).toBeLessThanOrEqual(
          effectiveCap(tier, hi),
        );
      }),
    );
  });
});

describe("plan-limits — nextTier ladder invariants (property)", () => {
  // The whole ladder is pinned behaviourally: index+1 climb, null at top.
  const expectedNext: Record<PlanTier, PlanTier | null> = {
    free: "solo",
    solo: "startup",
    startup: "scale",
    scale: "enterprise",
    enterprise: null,
  };

  it("climbs the ladder strictly and returns null only at the top", () => {
    fc.assert(
      fc.property(tierArb, (tier) => {
        const next = nextTier(tier);
        expect(next).toBe(expectedNext[tier]);
        // Null iff enterprise (top rung).
        expect(next === null).toBe(tier === "enterprise");
      }),
    );
  });

  it("climbing never lowers the plan limit", () => {
    fc.assert(
      fc.property(tierArb, (tier) => {
        const next = nextTier(tier);
        if (next !== null) {
          expect(PLAN_LIMITS[next]).toBeGreaterThanOrEqual(PLAN_LIMITS[tier]);
        }
      }),
    );
  });

  it("every non-enterprise tier's limit is within PLATFORM_HARD_CAP", () => {
    fc.assert(
      fc.property(
        fc.constantFrom<PlanTier>("free", "solo", "startup", "scale"),
        (tier) => {
          expect(PLAN_LIMITS[tier]).toBeLessThanOrEqual(PLATFORM_HARD_CAP);
        },
      ),
    );
  });

  // Negative control (anti-vacuity, AC6): the harness must be able to fail.
  it("negative control: a deliberately-false property throws", () => {
    expect(() =>
      fc.assert(fc.property(tierArb, () => false)),
    ).toThrow();
  });
});
