import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  getFlag,
  getFeatureFlags,
  getTeamWorkspaceAllowlist,
  isTeamWorkspaceInviteEnabled,
} from "./server";

describe("getFlag", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

  it("returns true when env var is '1'", () => {
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";
    expect(getFlag("kb-chat-sidebar")).toBe(true);
  });

  it("returns false when env var is '0'", () => {
    process.env.FLAG_KB_CHAT_SIDEBAR = "0";
    expect(getFlag("kb-chat-sidebar")).toBe(false);
  });

  it("returns false when env var is unset", () => {
    delete process.env.FLAG_KB_CHAT_SIDEBAR;
    expect(getFlag("kb-chat-sidebar")).toBe(false);
  });

  it("returns false when env var is any non-'1' value", () => {
    process.env.FLAG_KB_CHAT_SIDEBAR = "yes";
    expect(getFlag("kb-chat-sidebar")).toBe(false);

    process.env.FLAG_KB_CHAT_SIDEBAR = "true";
    expect(getFlag("kb-chat-sidebar")).toBe(false);
  });
});

describe("getFeatureFlags", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

  it("returns all flags as a record", () => {
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";
    delete process.env.FLAG_DEV_SIGNIN;
    delete process.env.FLAG_TEAM_WORKSPACE_INVITE;
    const flags = getFeatureFlags();
    expect(flags).toEqual({
      "kb-chat-sidebar": true,
      "dev-signin": false,
      "team-workspace-invite": false,
    });
  });

  it("returns false for all flags when none are set", () => {
    delete process.env.FLAG_KB_CHAT_SIDEBAR;
    delete process.env.FLAG_DEV_SIGNIN;
    delete process.env.FLAG_TEAM_WORKSPACE_INVITE;
    const flags = getFeatureFlags();
    expect(flags).toEqual({
      "kb-chat-sidebar": false,
      "dev-signin": false,
      "team-workspace-invite": false,
    });
  });

  it("includes team-workspace-invite as a registered flag", () => {
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    expect(getFlag("team-workspace-invite")).toBe(true);
    const flags = getFeatureFlags();
    expect(flags["team-workspace-invite"]).toBe(true);
  });
});

describe("getTeamWorkspaceAllowlist", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

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
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

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
