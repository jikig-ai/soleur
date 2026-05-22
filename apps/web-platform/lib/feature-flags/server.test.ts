import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

const mockGetIdentityFlags = vi.fn();

vi.mock("flagsmith-nodejs", () => {
  return {
    Flagsmith: vi.fn().mockImplementation(() => ({
      getIdentityFlags: mockGetIdentityFlags,
    })),
  };
});

import {
  getFlag,
  getRuntimeFlag,
  getFeatureFlags,
  ANON_IDENTITY,
  __resetForTests,
  type Identity,
} from "./server";

const PRD_USER: Identity = { userId: "user-prd-1", role: "prd" };
const DEV_USER: Identity = { userId: "user-dev-1", role: "dev" };

const ORIGINAL_ENV = process.env;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  mockGetIdentityFlags.mockReset();
  __resetForTests();
});

afterEach(() => {
  process.env = ORIGINAL_ENV;
});

describe("getFlag (env-only, sync)", () => {
  it("returns true when env var is '1'", () => {
    process.env.FLAG_DEV_SIGNIN = "1";
    expect(getFlag("dev-signin")).toBe(true);
  });

  it("returns false for unset or non-'1' values", () => {
    delete process.env.FLAG_DEV_SIGNIN;
    expect(getFlag("dev-signin")).toBe(false);
    for (const v of ["0", "true", "yes"]) {
      process.env.FLAG_DEV_SIGNIN = v;
      expect(getFlag("dev-signin")).toBe(false);
    }
  });
});

describe("getRuntimeFlag — identity-aware", () => {
  it("passes the user's identity + role trait to Flagsmith", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValueOnce({
      isFeatureEnabled: () => true,
    });

    await getRuntimeFlag("kb-chat-sidebar", DEV_USER);

    expect(mockGetIdentityFlags).toHaveBeenCalledWith("user-dev-1", { role: "dev" });
  });

  it("returns role-specific values for same flag", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockImplementation(async (_id: string, traits: { role: string }) => ({
      isFeatureEnabled: (name: string) =>
        name === "kb-chat-sidebar" && traits.role === "dev",
    }));

    await expect(getRuntimeFlag("kb-chat-sidebar", DEV_USER)).resolves.toBe(true);
    await expect(getRuntimeFlag("kb-chat-sidebar", PRD_USER)).resolves.toBe(false);
  });

  it("caches per-role: two prd calls = 1 SDK hit; one prd + one dev = 2", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: () => true });

    await getRuntimeFlag("kb-chat-sidebar", PRD_USER);
    await getRuntimeFlag("kb-chat-sidebar", PRD_USER);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(1);

    await getRuntimeFlag("kb-chat-sidebar", DEV_USER);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(2);
  });

  it("anonymous identity resolves through prd cache with 'anon' identifier", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValueOnce({ isFeatureEnabled: () => true });

    await getRuntimeFlag("kb-chat-sidebar", ANON_IDENTITY);

    expect(mockGetIdentityFlags).toHaveBeenCalledWith("anon", { role: "prd" });

    // Second anon call should hit the prd cache, not the SDK.
    await getRuntimeFlag("kb-chat-sidebar", ANON_IDENTITY);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(1);
  });

  it("falls back to env var when SDK throws", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";
    mockGetIdentityFlags.mockRejectedValueOnce(new Error("network blip"));

    await expect(getRuntimeFlag("kb-chat-sidebar", DEV_USER)).resolves.toBe(true);
  });

  it("falls back to env var when FLAGSMITH_ENVIRONMENT_KEY is unset (no SDK construction)", async () => {
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";

    await expect(getRuntimeFlag("kb-chat-sidebar", DEV_USER)).resolves.toBe(true);
    expect(mockGetIdentityFlags).not.toHaveBeenCalled();
  });

  it("fallback ignores role (env var = prd-segment mirror)", async () => {
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    process.env.FLAG_KB_CHAT_SIDEBAR = "0";

    await expect(getRuntimeFlag("kb-chat-sidebar", DEV_USER)).resolves.toBe(false);
    await expect(getRuntimeFlag("kb-chat-sidebar", PRD_USER)).resolves.toBe(false);
  });
});

describe("getFeatureFlags (combined per-identity snapshot)", () => {
  it("merges env-flag values with identity-resolved runtime-flag values", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    process.env.FLAG_DEV_SIGNIN = "1";
    process.env.FLAG_KB_CHAT_SIDEBAR = "0";
    mockGetIdentityFlags.mockResolvedValueOnce({
      isFeatureEnabled: (name: string) => name === "kb-chat-sidebar",
    });

    const flags = await getFeatureFlags(DEV_USER);
    expect(flags).toEqual({
      "dev-signin": true,
      "kb-chat-sidebar": true,
    });
  });

  it("anonymous returns prd snapshot + env-only flags", async () => {
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    process.env.FLAG_DEV_SIGNIN = "0";
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";

    const flags = await getFeatureFlags(ANON_IDENTITY);
    expect(flags).toEqual({
      "dev-signin": false,
      "kb-chat-sidebar": true,
    });
  });
});
