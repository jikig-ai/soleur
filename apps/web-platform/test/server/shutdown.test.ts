import { describe, expect, it } from "vitest";
import { WS_CLOSE_CODES } from "@/lib/types";
import { NON_TRANSIENT_CLOSE_CODES } from "@/lib/ws-client";

describe("Graceful shutdown close codes", () => {
  it("SERVER_GOING_AWAY equals 1001 (RFC 6455 Going Away)", () => {
    expect(WS_CLOSE_CODES.SERVER_GOING_AWAY).toBe(1001);
  });

  it("1001 is not in NON_TRANSIENT_CLOSE_CODES (client will auto-reconnect)", () => {
    expect(NON_TRANSIENT_CLOSE_CODES[1001]).toBeUndefined();
  });

  it("all WS_CLOSE_CODES values are unique", () => {
    const values = Object.values(WS_CLOSE_CODES);
    const unique = new Set(values);
    expect(unique.size).toBe(values.length);
  });
});
