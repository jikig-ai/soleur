import { describe, test, expect } from "vitest";

// WebSocket close code allocation — mirrors ws-handler.ts usage.
// These tests verify the allocation table is consistent, not the handler itself.
// Integration testing of the actual handler requires WS infrastructure.

describe("WebSocket close code allocation", () => {
  // Must stay in sync with ws-handler.ts
  const CLOSE_CODES: Record<string, number> = {
    AUTH_TIMEOUT: 4001,
    SUPERSEDED: 4002,
    AUTH_REQUIRED: 4003,
    TC_NOT_ACCEPTED: 4004,
    INTERNAL_ERROR: 4005,
  };

  test("all close codes are unique", () => {
    const codes = Object.values(CLOSE_CODES);
    expect(new Set(codes).size).toBe(codes.length);
  });

  test("all close codes are in the application-reserved range (4000-4999)", () => {
    for (const code of Object.values(CLOSE_CODES)) {
      expect(code).toBeGreaterThanOrEqual(4000);
      expect(code).toBeLessThanOrEqual(4999);
    }
  });
});
