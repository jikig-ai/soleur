import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resolveHostId, assertHostIdNotUserId } from "@/server/host-identity";

beforeEach(() => {
  vi.stubEnv("SOLEUR_HOST_ID", "");
  vi.stubEnv("NODE_ENV", "test");
});
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("resolveHostId (host-stable infra id, #5274 Phase 2)", () => {
  it("returns the injected SOLEUR_HOST_ID (the Hetzner server id)", () => {
    vi.stubEnv("SOLEUR_HOST_ID", "  12345678  "); // trims whitespace
    expect(resolveHostId()).toBe("12345678");
  });

  it("FAILS LOUD in production when SOLEUR_HOST_ID is unset (no per-container fallback)", () => {
    vi.stubEnv("NODE_ENV", "production");
    expect(() => resolveHostId()).toThrow(/SOLEUR_HOST_ID is unset in production/);
  });

  it("returns a stable non-prod sentinel when unset (dev/test), never a per-container value", () => {
    vi.stubEnv("NODE_ENV", "development");
    const id = resolveHostId();
    expect(id).toBe("dev-local");
    // Stable across calls (a per-container hostname would differ each time).
    expect(resolveHostId()).toBe(id);
  });
});

describe("assertHostIdNotUserId (the load-bearing DSAR boundary)", () => {
  const HETZNER_ID = "12345678";
  const USER_ID = "11111111-1111-4111-8111-111111111111";

  it("passes for a Hetzner integer host id vs a distinct user id", () => {
    expect(() => assertHostIdNotUserId(HETZNER_ID, USER_ID)).not.toThrow();
  });

  it("throws when host_id equals a user id", () => {
    expect(() => assertHostIdNotUserId(USER_ID, USER_ID)).toThrow(
      /host_id equals a user id/,
    );
  });

  it("throws when host_id is UUID-shaped (wrongly sourced from auth.uid())", () => {
    const otherUuid = "22222222-2222-4222-8222-222222222222";
    expect(() => assertHostIdNotUserId(otherUuid, USER_ID)).toThrow(
      /host_id is UUID-shaped/,
    );
  });

  it("passes for a 32-hex machine-id host id", () => {
    expect(() =>
      assertHostIdNotUserId("0123456789abcdef0123456789abcdef", USER_ID),
    ).not.toThrow();
  });
});
