import { describe, test, expect } from "vitest";
import { WS_CLOSE_CODES } from "../lib/types";

// WebSocket close code allocation — tests verify the shared constant is consistent.
// Integration testing of the actual handler requires WS infrastructure.

describe("WebSocket close code allocation", () => {
  test("all close codes are unique", () => {
    const codes = Object.values(WS_CLOSE_CODES);
    expect(new Set(codes).size).toBe(codes.length);
  });

  test("all close codes are in valid WebSocket ranges", () => {
    for (const [name, code] of Object.entries(WS_CLOSE_CODES)) {
      const isRfcStandard = code >= 1000 && code <= 2999;
      const isAppReserved = code >= 4000 && code <= 4999;
      expect(isRfcStandard || isAppReserved, `${name} (${code}) is not in a valid range`).toBe(true);
    }
  });
});
