import { describe, test, expect } from "bun:test";
import { computeFindingHash } from "../../skills/ux-audit/scripts/dedup-hash";

describe("computeFindingHash (sha256 of {route}|{selector}|{category})", () => {
  test("produces deterministic sha256 for a canonical triple", () => {
    const h = computeFindingHash({
      route: "/dashboard/kb",
      selector: "aside.sidebar",
      category: "real-estate",
    });
    expect(h).toMatch(/^[a-f0-9]{64}$/);
    expect(h).toBe(
      computeFindingHash({
        route: "/dashboard/kb",
        selector: "aside.sidebar",
        category: "real-estate",
      }),
    );
  });

  test("coarsens empty selector to '*' (one finding per {route,category})", () => {
    const withEmpty = computeFindingHash({
      route: "/dashboard",
      selector: "",
      category: "ia",
    });
    const withStar = computeFindingHash({
      route: "/dashboard",
      selector: "*",
      category: "ia",
    });
    expect(withEmpty).toBe(withStar);
  });

  test("different routes produce different hashes", () => {
    const a = computeFindingHash({ route: "/a", selector: "x", category: "real-estate" });
    const b = computeFindingHash({ route: "/b", selector: "x", category: "real-estate" });
    expect(a).not.toBe(b);
  });

  test("different selectors produce different hashes", () => {
    const a = computeFindingHash({ route: "/a", selector: "x", category: "real-estate" });
    const b = computeFindingHash({ route: "/a", selector: "y", category: "real-estate" });
    expect(a).not.toBe(b);
  });

  test("different categories produce different hashes", () => {
    const a = computeFindingHash({ route: "/a", selector: "x", category: "real-estate" });
    const b = computeFindingHash({ route: "/a", selector: "x", category: "ia" });
    expect(a).not.toBe(b);
  });

  test("rejects invalid category", () => {
    expect(() =>
      computeFindingHash({
        route: "/a",
        selector: "x",
        // @ts-expect-error — intentional invalid category
        category: "accessibility",
      }),
    ).toThrow(/category/i);
  });
});
