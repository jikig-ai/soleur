/**
 * #8211 T2 build 1 — `new-sessions-paused` is the quiet-window kill-switch.
 *
 * Contract: default OFF; ABSENT (no Flagsmith feature, no env mirror) means
 * sessions are allowed; the decision is global (identity-independent), so a
 * per-role or per-org override cannot split the fleet.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const mockGetIdentityFlags = vi.fn();

vi.mock("flagsmith-nodejs", () => ({
  Flagsmith: vi.fn().mockImplementation(function (
    this: Record<string, unknown>,
  ) {
    this.getIdentityFlags = mockGetIdentityFlags;
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));

import {
  isNewAgentSessionsPaused,
  __resetFeatureFlagsForTests,
} from "@/lib/feature-flags/server";

const ORIGINAL_ENV = process.env;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  delete process.env.FLAG_NEW_SESSIONS_PAUSED;
  delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
  mockGetIdentityFlags.mockReset();
  __resetFeatureFlagsForTests();
});

afterEach(() => {
  process.env = ORIGINAL_ENV;
});

describe("isNewAgentSessionsPaused", () => {
  it("absent everywhere (no Flagsmith key, no env) -> false: sessions allowed", async () => {
    await expect(isNewAgentSessionsPaused()).resolves.toBe(false);
  });

  it("env mirror FLAG_NEW_SESSIONS_PAUSED=1 (Flagsmith outage path) -> true", async () => {
    process.env.FLAG_NEW_SESSIONS_PAUSED = "1";
    await expect(isNewAgentSessionsPaused()).resolves.toBe(true);
  });

  it("env mirror 0 -> false", async () => {
    process.env.FLAG_NEW_SESSIONS_PAUSED = "0";
    await expect(isNewAgentSessionsPaused()).resolves.toBe(false);
  });

  it("Flagsmith reachable but the feature does not exist there (SDK reports disabled) -> false", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    // Mirrors flagsmith-nodejs Flags.getFlag: an unknown feature name yields
    // { enabled: false } rather than throwing (no defaultFlagHandler is set).
    mockGetIdentityFlags.mockResolvedValue({
      isFeatureEnabled: () => false,
    });
    await expect(isNewAgentSessionsPaused()).resolves.toBe(false);
  });

  it("Flagsmith feature enabled -> true, even if the env mirror says 0 (live path wins)", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    process.env.FLAG_NEW_SESSIONS_PAUSED = "0";
    mockGetIdentityFlags.mockResolvedValue({
      isFeatureEnabled: (name: string) => name === "new-sessions-paused",
    });
    await expect(isNewAgentSessionsPaused()).resolves.toBe(true);
  });

  it("asks Flagsmith with the anonymous prd identity (global, never per-user)", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: () => false });
    await isNewAgentSessionsPaused();
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(1);
    expect(mockGetIdentityFlags.mock.calls[0][0]).toBe("role:prd");
  });
});
