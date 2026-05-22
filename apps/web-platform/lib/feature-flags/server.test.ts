import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

const mockGetIdentityFlags = vi.fn();

vi.mock("flagsmith-nodejs", () => {
  return {
    Flagsmith: vi.fn().mockImplementation(() => ({
      getIdentityFlags: mockGetIdentityFlags,
    })),
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import {
  getFlag,
  getRuntimeFlag,
  getFeatureFlags,
  getTeamWorkspaceAllowlist,
  isTeamWorkspaceInviteEnabled,
  ANON_IDENTITY,
  __resetFeatureFlagsForTests,
  type Identity,
} from "./server";

const PRD_USER: Identity = { userId: "user-prd-1", role: "prd" };
const DEV_USER: Identity = { userId: "user-dev-1", role: "dev" };

const ORIGINAL_ENV = process.env;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  mockGetIdentityFlags.mockReset();
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

  it("includes team-workspace-invite as a registered env flag", () => {
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    expect(getFlag("team-workspace-invite")).toBe(true);
  });
});

describe("getRuntimeFlag — identity-aware", () => {
  it("passes role-prefixed identifier and role trait to Flagsmith (no userId leakage)", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValueOnce({
      isFeatureEnabled: () => true,
    });

    await getRuntimeFlag("kb-chat-sidebar", DEV_USER);

    expect(mockGetIdentityFlags).toHaveBeenCalledWith("role:dev", { role: "dev" });
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

  it("anonymous identity is forwarded with role=prd", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValueOnce({ isFeatureEnabled: () => true });

    await getRuntimeFlag("kb-chat-sidebar", ANON_IDENTITY);

    expect(mockGetIdentityFlags).toHaveBeenCalledWith("role:prd", { role: "prd" });
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
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "0";
    process.env.FLAG_KB_CHAT_SIDEBAR = "0";
    mockGetIdentityFlags.mockResolvedValueOnce({
      isFeatureEnabled: (name: string) => name === "kb-chat-sidebar",
    });

    const flags = await getFeatureFlags(DEV_USER);
    expect(flags).toEqual({
      "dev-signin": true,
      "team-workspace-invite": false,
      "kb-chat-sidebar": true,
    });
  });

  it("anonymous returns prd snapshot + env-only flags", async () => {
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    process.env.FLAG_DEV_SIGNIN = "0";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "0";
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";

    const flags = await getFeatureFlags(ANON_IDENTITY);
    expect(flags).toEqual({
      "dev-signin": false,
      "team-workspace-invite": false,
      "kb-chat-sidebar": true,
    });
  });

  it("returns false for all flags when none are set", async () => {
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    delete process.env.FLAG_KB_CHAT_SIDEBAR;
    delete process.env.FLAG_DEV_SIGNIN;
    delete process.env.FLAG_TEAM_WORKSPACE_INVITE;

    const flags = await getFeatureFlags(ANON_IDENTITY);
    expect(flags).toEqual({
      "dev-signin": false,
      "team-workspace-invite": false,
      "kb-chat-sidebar": false,
    });
  });
});

describe("getTeamWorkspaceAllowlist", () => {
  it("returns empty set when env var unset", () => {
    delete process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS;
    expect(getTeamWorkspaceAllowlist().size).toBe(0);
  });

  it("returns empty set when env var is empty string", () => {
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "";
    expect(getTeamWorkspaceAllowlist().size).toBe(0);
  });

  it("parses a single org id", () => {
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-1";
    const set = getTeamWorkspaceAllowlist();
    expect(set.has("org-1")).toBe(true);
    expect(set.size).toBe(1);
  });

  it("parses comma-separated org ids and trims whitespace", () => {
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-1, org-2 ,  org-3";
    const set = getTeamWorkspaceAllowlist();
    expect(set.has("org-1")).toBe(true);
    expect(set.has("org-2")).toBe(true);
    expect(set.has("org-3")).toBe(true);
    expect(set.size).toBe(3);
  });

  it("filters out empty segments from doubled commas", () => {
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-1,,org-2,";
    const set = getTeamWorkspaceAllowlist();
    expect(set.size).toBe(2);
    expect(set.has("")).toBe(false);
  });

  it("re-parses when the env var value changes (cache keyed on raw value)", () => {
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-1";
    expect(getTeamWorkspaceAllowlist().has("org-1")).toBe(true);
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-2";
    const set = getTeamWorkspaceAllowlist();
    expect(set.has("org-2")).toBe(true);
    expect(set.has("org-1")).toBe(false);
  });
});

describe("isTeamWorkspaceInviteEnabled", () => {
  it("returns false when flag is OFF (even if org is allowlisted) — AC-F", () => {
    delete process.env.FLAG_TEAM_WORKSPACE_INVITE;
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-jikigai";
    expect(isTeamWorkspaceInviteEnabled("org-jikigai")).toBe(false);
  });

  it("returns false when flag is ON but allowlist empty — AC-F", () => {
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "";
    expect(isTeamWorkspaceInviteEnabled("org-jikigai")).toBe(false);
  });

  it("returns false when flag is ON but orgId not in allowlist — AC-F", () => {
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-jikigai,org-other";
    expect(isTeamWorkspaceInviteEnabled("org-not-listed")).toBe(false);
  });

  it("returns true only when BOTH keys evaluate true — AC-F", () => {
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-jikigai";
    expect(isTeamWorkspaceInviteEnabled("org-jikigai")).toBe(true);
  });

  it("returns false for empty orgId argument", () => {
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-jikigai";
    expect(isTeamWorkspaceInviteEnabled("")).toBe(false);
  });
});
