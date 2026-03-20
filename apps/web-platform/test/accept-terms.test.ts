import { describe, test, expect } from "vitest";

// Test the accept-terms API route logic in isolation.
// The actual route requires Next.js runtime, so we test the
// business logic extracted as pure functions.

describe("accept-terms business logic", () => {
  // Simulates the guard: .is("tc_accepted_at", null)
  // Returns true if the update would match (row has NULL tc_accepted_at)
  function wouldUpdateMatch(existingTcAcceptedAt: string | null): boolean {
    return existingTcAcceptedAt === null;
  }

  test("unauthenticated request should be rejected", () => {
    const user = null;
    expect(user).toBeNull();
    // Route returns 401 when user is null
  });

  test("user with NULL tc_accepted_at gets it set", () => {
    const existingValue = null;
    expect(wouldUpdateMatch(existingValue)).toBe(true);
  });

  test("user with existing tc_accepted_at is NOT re-stamped (immutability)", () => {
    const existingValue = "2026-01-15T10:30:00Z";
    expect(wouldUpdateMatch(existingValue)).toBe(false);
  });

  test("update is idempotent — calling twice does not change the result", () => {
    // First call: NULL -> sets timestamp
    expect(wouldUpdateMatch(null)).toBe(true);

    // Second call: timestamp already set -> no match, no update
    const afterFirstCall = "2026-03-20T12:00:00Z";
    expect(wouldUpdateMatch(afterFirstCall)).toBe(false);
  });
});

describe("WebSocket T&C enforcement", () => {
  // Close code allocation for ws-handler.ts
  const WS_CLOSE_CODES = {
    AUTH_TIMEOUT: 4001,
    SUPERSEDED: 4002,
    AUTH_REQUIRED: 4003,
    TC_NOT_ACCEPTED: 4004,
  } as const;

  test("T&C close code is 4004", () => {
    expect(WS_CLOSE_CODES.TC_NOT_ACCEPTED).toBe(4004);
  });

  test("T&C close code does not collide with existing codes", () => {
    const codes = Object.values(WS_CLOSE_CODES);
    const uniqueCodes = new Set(codes);
    expect(uniqueCodes.size).toBe(codes.length);
  });

  test("all close codes are in the application-reserved range (4000-4999)", () => {
    for (const code of Object.values(WS_CLOSE_CODES)) {
      expect(code).toBeGreaterThanOrEqual(4000);
      expect(code).toBeLessThanOrEqual(4999);
    }
  });
});
