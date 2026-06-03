import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { renderHook, act } from "@testing-library/react";
import {
  useRailWidth,
  clampRailWidth,
  railMaxPx,
  RAIL_WIDTH_KEY,
  RAIL_DEFAULT_PX,
  RAIL_MIN_PX,
  RAIL_MAX_ABS_PX,
} from "@/hooks/use-rail-width";

// Widenable KB rail (amendment). The hook mirrors useSidebarCollapse: a
// useState default, a post-hydration localStorage read, and a setter that
// clamps to [RAIL_MIN_PX, railMaxPx()] then persists. Width is a single integer
// under the `soleur:sidebar.kb.width` key — subordinate to collapse (the layout
// gates the inline width on `drill === "kb" && !collapsed`).

describe("clampRailWidth (pure, deterministic via explicit viewport)", () => {
  it("clamps an oversized value to the viewport-derived max (AC11)", () => {
    // max = min(RAIL_MAX_ABS_PX 480, floor(1280 * 0.4) = 512) = 480
    expect(clampRailWidth(9999, 1280)).toBe(480);
    expect(railMaxPx(1280)).toBe(480);
  });

  it("clamps a tiny value up to RAIL_MIN_PX so widening never narrows below today's default (AC11)", () => {
    expect(clampRailWidth(10, 1280)).toBe(RAIL_MIN_PX);
    expect(RAIL_MIN_PX).toBeGreaterThanOrEqual(RAIL_DEFAULT_PX);
  });

  it("passes through an in-range value (rounded)", () => {
    expect(clampRailWidth(300.6, 1280)).toBe(301);
  });

  it("never lets the 40vw max fall below the min on a tiny viewport", () => {
    // floor(400 * 0.4) = 160 < min → max pinned to RAIL_MIN_PX
    expect(railMaxPx(400)).toBe(RAIL_MIN_PX);
    expect(clampRailWidth(9999, 400)).toBe(RAIL_MIN_PX);
  });

  it("returns the default for NaN input", () => {
    expect(clampRailWidth(Number.NaN, 1280)).toBe(RAIL_DEFAULT_PX);
  });
});

describe("useRailWidth", () => {
  beforeEach(() => {
    localStorage.clear();
  });
  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("defaults to RAIL_DEFAULT_PX (224) with no stored value", () => {
    const { result } = renderHook(() => useRailWidth());
    expect(result.current[0]).toBe(RAIL_DEFAULT_PX);
  });

  it("hydrates a stored in-range width on mount", () => {
    localStorage.setItem(RAIL_WIDTH_KEY, "320");
    const { result } = renderHook(() => useRailWidth());
    expect(result.current[0]).toBe(320);
  });

  it("clamps a stored over-range width on read, never applying the raw value (AC11)", () => {
    localStorage.setItem(RAIL_WIDTH_KEY, "9999");
    const { result } = renderHook(() => useRailWidth());
    const w = result.current[0];
    expect(w).not.toBe(9999);
    expect(w).toBeLessThanOrEqual(RAIL_MAX_ABS_PX);
    expect(w).toBeGreaterThanOrEqual(RAIL_MIN_PX);
  });

  it("clamps a stored under-range width up to RAIL_MIN_PX on read (AC11)", () => {
    localStorage.setItem(RAIL_WIDTH_KEY, "10");
    const { result } = renderHook(() => useRailWidth());
    expect(result.current[0]).toBe(RAIL_MIN_PX);
  });

  it("setWidth clamps and persists the clamped value (AC10)", () => {
    const { result } = renderHook(() => useRailWidth());
    act(() => result.current[1](360));
    expect(result.current[0]).toBe(360);
    expect(localStorage.getItem(RAIL_WIDTH_KEY)).toBe("360");

    act(() => result.current[1](99999));
    expect(result.current[0]).toBeLessThanOrEqual(RAIL_MAX_ABS_PX);
    expect(localStorage.getItem(RAIL_WIDTH_KEY)).toBe(String(result.current[0]));
  });

  it("setWidth(px, false) updates state transiently WITHOUT persisting (drag preview)", () => {
    const { result } = renderHook(() => useRailWidth());
    act(() => result.current[1](300, false));
    expect(result.current[0]).toBe(300);
    expect(localStorage.getItem(RAIL_WIDTH_KEY)).toBeNull();
  });

  it("re-clamps the applied width against the live viewport on resize, preserving stored intent", () => {
    const originalWidth = window.innerWidth;
    const setViewport = (w: number) =>
      Object.defineProperty(window, "innerWidth", {
        value: w,
        configurable: true,
        writable: true,
      });
    // Pin a wide viewport so 400 fits (railMaxPx(1280) = 480) at hydration,
    // independent of the test env's default innerWidth.
    setViewport(1280);
    localStorage.setItem(RAIL_WIDTH_KEY, "400");
    const { result } = renderHook(() => useRailWidth());
    expect(result.current[0]).toBe(400);

    // Shrink the viewport so 40vw falls below the stored width → clamp kicks in.
    act(() => {
      setViewport(500);
      window.dispatchEvent(new Event("resize"));
    });
    // railMaxPx(500) = max(224, min(480, 200)) = 224 → applied width clamps down,
    // but the stored INTENT (400) is untouched so a grow-back restores it.
    expect(result.current[0]).toBe(224);
    expect(localStorage.getItem(RAIL_WIDTH_KEY)).toBe("400");

    // Grow the viewport back → the stored 400 intent is re-applied.
    act(() => {
      setViewport(1280);
      window.dispatchEvent(new Event("resize"));
    });
    expect(result.current[0]).toBe(400);

    setViewport(originalWidth);
  });

  it("is private-mode safe — a throwing localStorage does not crash the hook", () => {
    const throwingStorage = {
      getItem: () => {
        throw new Error("blocked");
      },
      setItem: () => {
        throw new Error("blocked");
      },
      removeItem: () => {
        throw new Error("blocked");
      },
      // afterEach calls localStorage.clear() before unstubbing — provide a no-op
      // so cleanup doesn't throw on the private-mode stub.
      clear: () => {},
    };
    vi.stubGlobal("localStorage", throwingStorage);
    const { result } = renderHook(() => useRailWidth());
    expect(result.current[0]).toBe(RAIL_DEFAULT_PX);
    expect(() => act(() => result.current[1](300))).not.toThrow();
  });
});
