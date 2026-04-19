import { describe, test, expect } from "vitest";
import {
  PLAN_LIMITS,
  PLATFORM_HARD_CAP,
  effectiveCap,
  nextTier,
} from "../lib/plan-limits";

describe("PLAN_LIMITS", () => {
  test("ladder values are pinned", () => {
    expect(PLAN_LIMITS.free).toBe(1);
    expect(PLAN_LIMITS.solo).toBe(2);
    expect(PLAN_LIMITS.startup).toBe(5);
    expect(PLAN_LIMITS.scale).toBe(50);
    expect(PLAN_LIMITS.enterprise).toBe(50);
  });

  test("PLATFORM_HARD_CAP is 50", () => {
    expect(PLATFORM_HARD_CAP).toBe(50);
  });
});

describe("effectiveCap", () => {
  test("null override falls back to tier default", () => {
    expect(effectiveCap("solo", null)).toBe(2);
    expect(effectiveCap("free", null)).toBe(1);
    expect(effectiveCap("scale", null)).toBe(50);
  });

  test("override above tier default applies (raise-only)", () => {
    expect(effectiveCap("solo", 100)).toBe(100);
    expect(effectiveCap("enterprise", 200)).toBe(200);
  });

  test("override below tier default is ignored (raise-only)", () => {
    expect(effectiveCap("solo", 0)).toBe(2);
    expect(effectiveCap("startup", 3)).toBe(5);
  });

  test("undefined tier defaults to free cap of 1", () => {
    expect(effectiveCap(undefined, null)).toBe(1);
  });
});

describe("nextTier", () => {
  test("ladder progression", () => {
    expect(nextTier("free")).toBe("solo");
    expect(nextTier("solo")).toBe("startup");
    expect(nextTier("startup")).toBe("scale");
    expect(nextTier("scale")).toBe("enterprise");
  });

  test("enterprise returns null (top of ladder)", () => {
    expect(nextTier("enterprise")).toBeNull();
  });
});
