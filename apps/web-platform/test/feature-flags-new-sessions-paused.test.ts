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

describe("isNewAgentSessionsPaused: a failing Flagsmith never re-opens the gate (review P1)", () => {
  const live = (on: boolean) => ({ isFeatureEnabled: (n: string) => n === "new-sessions-paused" && on });

  it("a 200 ms timeout AFTER Flagsmith said ON keeps the gate ON despite a mirror of 0", async () => {
    vi.useFakeTimers();
    try {
      process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
      process.env.FLAG_NEW_SESSIONS_PAUSED = "0";
      mockGetIdentityFlags.mockResolvedValueOnce(live(true));
      await expect(isNewAgentSessionsPaused()).resolves.toBe(true);
      // The 30 s snapshot cache expires and the next fetch times out: the env-mirror snapshot is built.
      vi.advanceTimersByTime(31_000);
      mockGetIdentityFlags.mockRejectedValueOnce(new Error("timeout"));
      await expect(isNewAgentSessionsPaused()).resolves.toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  it("the held value expires after 10 minutes of continuous failure, then the mirror decides", async () => {
    vi.useFakeTimers();
    try {
      process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
      process.env.FLAG_NEW_SESSIONS_PAUSED = "0";
      mockGetIdentityFlags.mockResolvedValueOnce(live(true));
      await isNewAgentSessionsPaused();
      mockGetIdentityFlags.mockRejectedValue(new Error("down"));
      vi.advanceTimersByTime(31_000);
      await expect(isNewAgentSessionsPaused()).resolves.toBe(true);
      vi.advanceTimersByTime(11 * 60_000);
      await expect(isNewAgentSessionsPaused()).resolves.toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });

  it("the mirror can turn the gate ON during a failure but a held OFF never wins over a mirror of 1", async () => {
    vi.useFakeTimers();
    try {
      process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
      process.env.FLAG_NEW_SESSIONS_PAUSED = "0";
      mockGetIdentityFlags.mockResolvedValueOnce(live(false));
      await expect(isNewAgentSessionsPaused()).resolves.toBe(false);
      process.env.FLAG_NEW_SESSIONS_PAUSED = "1";
      vi.advanceTimersByTime(31_000);
      mockGetIdentityFlags.mockRejectedValueOnce(new Error("timeout"));
      await expect(isNewAgentSessionsPaused()).resolves.toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  it("when Flagsmith answers OFF after having said ON, OFF wins (the owner turned it off)", async () => {
    vi.useFakeTimers();
    try {
      process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
      mockGetIdentityFlags.mockResolvedValueOnce(live(true));
      await expect(isNewAgentSessionsPaused()).resolves.toBe(true);
      vi.advanceTimersByTime(31_000);
      mockGetIdentityFlags.mockResolvedValueOnce(live(false));
      await expect(isNewAgentSessionsPaused()).resolves.toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });
});
