import { describe, it, expect } from "vitest";
import { stripBodyHeaders } from "@/server/share-route-helpers";

describe("stripBodyHeaders", () => {
  it("removes Content-Type and Content-Length", () => {
    const input = new Headers({
      "Content-Type": "application/json",
      "Content-Length": "42",
    });
    const result = stripBodyHeaders(input);
    expect(result.get("Content-Type")).toBeNull();
    expect(result.get("Content-Length")).toBeNull();
  });

  it("preserves unrelated headers (e.g., Retry-After, X-RateLimit)", () => {
    const input = new Headers({
      "Content-Type": "application/json",
      "Content-Length": "42",
      "Retry-After": "30",
      "X-RateLimit-Remaining": "5",
      "Cache-Control": "no-store",
    });
    const result = stripBodyHeaders(input);
    expect(result.get("Retry-After")).toBe("30");
    expect(result.get("X-RateLimit-Remaining")).toBe("5");
    expect(result.get("Cache-Control")).toBe("no-store");
  });

  it("does not mutate the source Headers instance", () => {
    const input = new Headers({ "Content-Type": "application/json" });
    stripBodyHeaders(input);
    expect(input.get("Content-Type")).toBe("application/json");
  });

  it("is a no-op when the body headers are already absent", () => {
    const input = new Headers({ "X-Custom": "ok" });
    const result = stripBodyHeaders(input);
    expect(result.get("X-Custom")).toBe("ok");
  });
});
