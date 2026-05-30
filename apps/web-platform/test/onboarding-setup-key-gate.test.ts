import { describe, test, expect } from "vitest";
import { shouldRouteToSetupKey } from "@/lib/onboarding/setup-key-gate";

// feat-skip-api-key-onboarding (#4642) — AC3. The onboarding api-key step
// (redirect to /setup-key) is shown ONLY when the user has no effective key
// AND has not chosen "Set up later". Pure decision shared by the callback +
// accept-terms redirect gates so all four states are unit-covered.

describe("shouldRouteToSetupKey (AC3)", () => {
  test("own/effective key, not skipped → false (skip the step)", () => {
    expect(shouldRouteToSetupKey({ hasEffectiveKey: true, setupKeySkippedAt: null })).toBe(false);
  });

  test("delegated (effective key), not skipped → false (never trap a delegated user)", () => {
    // Regression for the pre-existing bug: a no-own-key accepted-delegation
    // user was force-redirected to /setup-key.
    expect(shouldRouteToSetupKey({ hasEffectiveKey: true, setupKeySkippedAt: null })).toBe(false);
  });

  test("keyless, not skipped → true (show the step)", () => {
    expect(shouldRouteToSetupKey({ hasEffectiveKey: false, setupKeySkippedAt: null })).toBe(true);
  });

  test("keyless, skipped → false (honor 'Set up later')", () => {
    expect(
      shouldRouteToSetupKey({ hasEffectiveKey: false, setupKeySkippedAt: "2026-05-30T00:00:00Z" }),
    ).toBe(false);
  });

  test("effective key AND skipped → false", () => {
    expect(
      shouldRouteToSetupKey({ hasEffectiveKey: true, setupKeySkippedAt: "2026-05-30T00:00:00Z" }),
    ).toBe(false);
  });
});
