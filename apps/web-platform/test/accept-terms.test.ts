import { describe, test, expect } from "vitest";
import { WS_CLOSE_CODES } from "../lib/types";

// WebSocket close code allocation — tests verify the shared constant is consistent.
// Integration testing of the actual handler requires WS infrastructure.

describe("WebSocket close code allocation", () => {
  test("all close codes are unique", () => {
    const codes = Object.values(WS_CLOSE_CODES);
    expect(new Set(codes).size).toBe(codes.length);
  });

  test("all close codes are in the application-reserved range (4000-4999)", () => {
    for (const code of Object.values(WS_CLOSE_CODES)) {
      expect(code).toBeGreaterThanOrEqual(4000);
      expect(code).toBeLessThanOrEqual(4999);
    }
  });
});
