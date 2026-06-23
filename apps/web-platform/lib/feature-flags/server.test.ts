import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

const mockGetIdentityFlags = vi.fn();

vi.mock("flagsmith-nodejs", () => {
  return {
    // vitest 4: mocks invoked with `new` now construct an instance, so a
    // constructor mock must use the `function` keyword and assign to `this`
    // (an arrow returning an object throws "is not a constructor").
    Flagsmith: vi.fn().mockImplementation(function (
      this: Record<string, unknown>,
    ) {
      this.getIdentityFlags = mockGetIdentityFlags;
    }),
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));

import {
  reportSilentFallback,
  mirrorWarnWithDebounce,
} from "@/server/observability";
import {
  getFlag,
  getRuntimeFlag,
  getFeatureFlags,
  isTeamWorkspaceInviteEnabled,
  isByokDelegationsEnabled,
  ANON_IDENTITY,
  __resetFeatureFlagsForTests,
  type Identity,
} from "./server";

const mockReportSilentFallback = vi.mocked(reportSilentFallback);
const mockMirrorWarnWithDebounce = vi.mocked(mirrorWarnWithDebounce);

const PRD_USER: Identity = { userId: "user-prd-1", role: "prd", orgId: null };
const DEV_USER: Identity = { userId: "user-dev-1", role: "dev", orgId: null };
const ORG_USER: Identity = { userId: "user-org-1", role: "prd", orgId: "org-123" };
const ORG_DEV: Identity = { userId: "user-dev-2", role: "dev", orgId: "org-456" };

const ORIGINAL_ENV = process.env;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  mockGetIdentityFlags.mockReset();
  mockReportSilentFallback.mockReset();
  mockMirrorWarnWithDebounce.mockReset();
  __resetFeatureFlagsForTests();
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
  it("passes role-prefixed identifier and role trait to Flagsmith with transient=true", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValueOnce({
      isFeatureEnabled: () => true,
    });

    await getRuntimeFlag("kb-chat-sidebar", DEV_USER);

    expect(mockGetIdentityFlags).toHaveBeenCalledWith("role:dev", { role: "dev" }, true);
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

  it("caches per (role,orgId): two same-key calls = 1 SDK hit; different key = 2", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: () => true });

    await getRuntimeFlag("kb-chat-sidebar", PRD_USER);
    await getRuntimeFlag("kb-chat-sidebar", PRD_USER);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(1);

    await getRuntimeFlag("kb-chat-sidebar", DEV_USER);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(2);
  });

  it("anonymous identity is forwarded with role=prd and transient=true", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValueOnce({ isFeatureEnabled: () => true });

    await getRuntimeFlag("kb-chat-sidebar", ANON_IDENTITY);

    expect(mockGetIdentityFlags).toHaveBeenCalledWith("role:prd", { role: "prd" }, true);
  });

  it("anonymous calls share the prd cache bucket (no second SDK hit)", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValueOnce({ isFeatureEnabled: () => true });

    await getRuntimeFlag("kb-chat-sidebar", ANON_IDENTITY);
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
    mockGetIdentityFlags.mockResolvedValueOnce({
      isFeatureEnabled: (name: string) => name === "kb-chat-sidebar",
    });

    const flags = await getFeatureFlags(DEV_USER);
    expect(flags).toEqual({
      "dev-signin": true,
      "team-workspace-invite": false,
      "kb-chat-sidebar": true,
      "byok-delegations": false,
      "c4-visualizer": false,
      "debug-mode": false,
      "c4-edit": false,
      "command-palette": false,
    });
  });

  it("anonymous returns prd snapshot + env-only flags", async () => {
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    process.env.FLAG_DEV_SIGNIN = "0";
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    process.env.FLAG_BYOK_DELEGATIONS = "1";

    const flags = await getFeatureFlags(ANON_IDENTITY);
    expect(flags).toEqual({
      "dev-signin": false,
      "team-workspace-invite": true,
      "kb-chat-sidebar": true,
      "byok-delegations": true,
      "c4-visualizer": false,
      "debug-mode": false,
      "c4-edit": false,
      "command-palette": false,
    });
  });

  it("returns false for all flags when none are set", async () => {
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    delete process.env.FLAG_KB_CHAT_SIDEBAR;
    delete process.env.FLAG_DEV_SIGNIN;
    delete process.env.FLAG_TEAM_WORKSPACE_INVITE;
    delete process.env.FLAG_BYOK_DELEGATIONS;

    const flags = await getFeatureFlags(ANON_IDENTITY);
    expect(flags).toEqual({
      "dev-signin": false,
      "team-workspace-invite": false,
      "kb-chat-sidebar": false,
      "byok-delegations": false,
      "c4-visualizer": false,
      "debug-mode": false,
      "c4-edit": false,
      "command-palette": false,
    });
  });

  it("AC1 — c4-edit is a member of the runtime snapshot", async () => {
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    const flags = await getFeatureFlags(ANON_IDENTITY);
    expect("c4-edit" in flags).toBe(true);
  });
});

describe("isTeamWorkspaceInviteEnabled (async, single-control)", () => {
  it("returns true when Flagsmith=ON", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({
      isFeatureEnabled: (n: string) => n === "team-workspace-invite",
    });
    await expect(isTeamWorkspaceInviteEnabled("org-jikigai", ORG_USER)).resolves.toBe(true);
  });

  it("returns false when Flagsmith=OFF", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({
      isFeatureEnabled: () => false,
    });
    await expect(isTeamWorkspaceInviteEnabled("org-jikigai", ORG_USER)).resolves.toBe(false);
  });

  it("returns false when orgId is empty", async () => {
    await expect(isTeamWorkspaceInviteEnabled("", ORG_USER)).resolves.toBe(false);
  });

  it("Flagsmith outage → env-fallback", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    mockGetIdentityFlags.mockRejectedValue(new Error("outage"));
    await expect(isTeamWorkspaceInviteEnabled("org-jikigai", ORG_USER)).resolves.toBe(true);
  });
});

describe("isByokDelegationsEnabled (async, single-control)", () => {
  it("returns true when Flagsmith=ON", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({
      isFeatureEnabled: (n: string) => n === "byok-delegations",
    });
    await expect(isByokDelegationsEnabled("org-123", ORG_USER)).resolves.toBe(true);
  });

  it("returns false when Flagsmith=OFF", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({
      isFeatureEnabled: () => false,
    });
    await expect(isByokDelegationsEnabled("org-123", ORG_USER)).resolves.toBe(false);
  });

  it("returns false when orgId is null", async () => {
    await expect(isByokDelegationsEnabled(null, PRD_USER)).resolves.toBe(false);
  });

  it("Flagsmith outage → env-fallback", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    process.env.FLAG_BYOK_DELEGATIONS = "1";
    mockGetIdentityFlags.mockRejectedValue(new Error("outage"));
    await expect(isByokDelegationsEnabled("org-123", ORG_USER)).resolves.toBe(true);
  });
});

describe("getRuntimeFlag — orgId trait forwarding + LRU", () => {
  it("passes orgId in traits and transient=true when orgId present", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: () => true });

    await getRuntimeFlag("team-workspace-invite", ORG_USER);

    expect(mockGetIdentityFlags).toHaveBeenCalledWith(
      "org:org-123:prd",
      { role: "prd", orgId: "org-123" },
      true,
    );
  });

  it("uses role-only identifier when orgId is null", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: () => true });

    await getRuntimeFlag("team-workspace-invite", PRD_USER);

    expect(mockGetIdentityFlags).toHaveBeenCalledWith(
      "role:prd",
      { role: "prd" },
      true,
    );
  });

  it("LRU cache key is (role,orgId) — same pair = cache hit, different orgId = miss", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: () => true });

    const user1: Identity = { userId: "u1", role: "prd", orgId: "org-A" };
    const user2: Identity = { userId: "u2", role: "prd", orgId: "org-A" };
    const user3: Identity = { userId: "u3", role: "prd", orgId: "org-B" };

    await getRuntimeFlag("team-workspace-invite", user1);
    await getRuntimeFlag("team-workspace-invite", user2);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(1);

    await getRuntimeFlag("team-workspace-invite", user3);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(2);
  });

  it("LRU eviction at FLAGSMITH_CACHE_MAX_ENTRIES=3", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    process.env.FLAGSMITH_CACHE_MAX_ENTRIES = "3";
    __resetFeatureFlagsForTests();
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: () => true });

    const ids: Identity[] = [
      { userId: "u1", role: "prd", orgId: "org-1" },
      { userId: "u2", role: "prd", orgId: "org-2" },
      { userId: "u3", role: "prd", orgId: "org-3" },
      { userId: "u4", role: "prd", orgId: "org-4" },
    ];

    for (const id of ids) await getRuntimeFlag("team-workspace-invite", id);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(4);

    await getRuntimeFlag("team-workspace-invite", ids[0]!);
    expect(mockGetIdentityFlags).toHaveBeenCalledTimes(5);
  });
});

describe("getIdentityFlags timeout → warn-level debounced mirror (Sentry-bug regression)", () => {
  // Production Sentry ID ac2d712121d94ad9ab154a16f6178fa7: a 200ms Flagsmith
  // timeout on /login was reported at error level via reportSilentFallback,
  // with no debounce, flooding Sentry and tripping the alert. The recovered
  // env-fallback path must instead emit a single warn-level debounced mirror.
  function timeoutError(): Error {
    // Message mirrors the SDK's re-thrown wrapper. The catch labels EVERY
    // getIdentityFlags rejection with the same errorClass regardless of cause;
    // on the 200ms-ceiling path a timeout is the dominant case (the code does
    // not inspect the cause chain).
    return new Error(
      "getIdentityFlags failed and no default flag handler was provided",
    );
  }

  it("AC1 — reports the recovered timeout via the warn-path helper, not the error-path helper", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockRejectedValueOnce(timeoutError());

    await getFeatureFlags(ANON_IDENTITY);

    expect(mockMirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();

    const [err, ctx, key, errorClass] = mockMirrorWarnWithDebounce.mock.calls[0]!;
    expect(err).toBeInstanceOf(Error);
    expect(ctx).toMatchObject({
      feature: "feature-flags",
      op: "flagsmith.getIdentityFlags",
      extra: { role: "prd", orgId: null },
    });
    // Dedup key is the per-segment snapshot cache key shape, never a userId.
    expect(key).toBe("prd:__anon__");
    expect(errorClass).toBe("flagsmith:getidentityflags-timeout");
  });

  it("AC2 — getFeatureFlags resolves with the env fallback snapshot and does not reject", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "0";
    process.env.FLAG_BYOK_DELEGATIONS = "0";
    process.env.FLAG_DEV_SIGNIN = "0";
    mockGetIdentityFlags.mockRejectedValueOnce(timeoutError());

    const flags = await getFeatureFlags(ANON_IDENTITY);

    expect(flags).toEqual({
      "dev-signin": false,
      "kb-chat-sidebar": true,
      "team-workspace-invite": false,
      "byok-delegations": false,
      "c4-visualizer": false,
      "debug-mode": false,
      "c4-edit": false,
      "command-palette": false,
    });
  });

  it("AC3 — delegates debounce with a stable per-(role,orgId) key; distinct identities get distinct keys", async () => {
    // The actual coalescing window is owned by mirrorWarnWithDebounce and
    // covered in test/observability-mirror-debounce.test.ts. Here we prove the
    // call site passes a STABLE key for the same segment (so the helper can
    // coalesce) and a DISTINCT key per segment (so it does not over-coalesce).
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockRejectedValue(timeoutError());

    await getFeatureFlags(ANON_IDENTITY);
    __resetFeatureFlagsForTests(); // drop snapshot cache so the next call re-enters fetch
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    await getFeatureFlags(ANON_IDENTITY);

    const anonKeys = mockMirrorWarnWithDebounce.mock.calls.map((c) => c[2]);
    expect(anonKeys).toEqual(["prd:__anon__", "prd:__anon__"]);

    await getFeatureFlags({ userId: "u-org", role: "prd", orgId: "org-123" });
    const lastKey = mockMirrorWarnWithDebounce.mock.calls.at(-1)![2];
    expect(lastKey).toBe("prd:org-123");
  });

  it("AC5 — no defaultFlagHandler is configured on the SDK client", async () => {
    // Guards against re-introducing the rejected approach: the app-level catch
    // + env fallback remains the degradation mechanism.
    const { Flagsmith } = await import("flagsmith-nodejs");
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValueOnce({ isFeatureEnabled: () => true });

    await getRuntimeFlag("kb-chat-sidebar", ANON_IDENTITY);

    const ctorArg = vi.mocked(Flagsmith).mock.calls[0]![0] as Record<string, unknown>;
    expect(ctorArg).not.toHaveProperty("defaultFlagHandler");
  });
});
