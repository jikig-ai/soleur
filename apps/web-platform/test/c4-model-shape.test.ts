import { describe, it, expect } from "vitest";
import { c4ModelCounts, MODEL_LEVEL_LINE } from "@/lib/c4-model-shape";

// Shared by the server re-render's refusal gates and the project read route's
// zero-view diagnostic (#8740): a wrong count here either commits a zero-view
// model or shows a false diagnostic.
describe("c4ModelCounts", () => {
  it.each([
    ["null model", null, { elements: 0, views: 0 }],
    ["string model", "x", { elements: 0, views: 0 }],
    ["array model", [{ elements: { a: 1 } }], { elements: 0, views: 0 }],
    ["empty model", {}, { elements: 0, views: 0 }],
    ["plain objects", { elements: { a: 1, b: 2 }, views: { index: {} } }, { elements: 2, views: 1 }],
    ["array members count as zero", { elements: ["a"], views: ["index"] }, { elements: 0, views: 0 }],
    ["string members count as zero", { elements: "ab", views: "cd" }, { elements: 0, views: 0 }],
    ["null members count as zero", { elements: null, views: null }, { elements: 0, views: 0 }],
  ])("%s", (_label, model, expected) => {
    expect(c4ModelCounts(model)).toEqual(expected);
  });

  it("MODEL_LEVEL_LINE is 0, below every real source line", () => {
    expect(MODEL_LEVEL_LINE).toBe(0);
  });
});
