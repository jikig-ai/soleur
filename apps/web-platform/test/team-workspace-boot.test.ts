/**
 * Phase 4 (#4229) — Boot-time Sentry breadcrumb for the
 * team-workspace-invite two-key feature gate.
 *
 * Per plan §Phase 4: "Boot-time Sentry breadcrumb when both keys
 * evaluate true in prd (helps catch typo-flip of env on prd)."
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const addBreadcrumbSpy = vi.fn();
const captureMessageSpy = vi.fn();

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: (...args: unknown[]) => addBreadcrumbSpy(...args),
  captureMessage: (...args: unknown[]) => captureMessageSpy(...args),
  captureException: vi.fn(),
}));

import { emitTeamWorkspaceInviteBootBreadcrumb } from "../server/team-workspace-boot";
import { __resetFeatureFlagsForTests } from "@/lib/feature-flags/server";

const ORIGINAL_ENV = process.env;
const mutableEnv = process.env as Record<string, string | undefined>;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
  __resetFeatureFlagsForTests();
  addBreadcrumbSpy.mockClear();
  captureMessageSpy.mockClear();
});

afterEach(() => {
  process.env = ORIGINAL_ENV;
});

describe("emitTeamWorkspaceInviteBootBreadcrumb (#4229 Phase 4 AC-F)", () => {
  it("no-op when NODE_ENV != production (even if both keys ON)", async () => {
    mutableEnv.NODE_ENV = "development";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-jikigai";
    await emitTeamWorkspaceInviteBootBreadcrumb();
    expect(addBreadcrumbSpy).not.toHaveBeenCalled();
  });

  it("no-op in production when flag OFF", async () => {
    mutableEnv.NODE_ENV = "production";
    delete process.env.FLAG_TEAM_WORKSPACE_INVITE;
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-jikigai";
    await emitTeamWorkspaceInviteBootBreadcrumb();
    expect(addBreadcrumbSpy).not.toHaveBeenCalled();
  });

  it("no-op in production when flag ON but allowlist empty", async () => {
    mutableEnv.NODE_ENV = "production";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    delete process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS;
    await emitTeamWorkspaceInviteBootBreadcrumb();
    expect(addBreadcrumbSpy).not.toHaveBeenCalled();
  });

  it("emits breadcrumb in production when both keys evaluate true", async () => {
    mutableEnv.NODE_ENV = "production";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = "org-jikigai,org-other";
    await emitTeamWorkspaceInviteBootBreadcrumb();
    expect(addBreadcrumbSpy).toHaveBeenCalledTimes(1);
    const [crumb] = addBreadcrumbSpy.mock.calls[0]!;
    expect(crumb).toMatchObject({
      category: "feature-flag",
      level: "info",
      message: "team-workspace-invite two-key gate ON in production",
      data: expect.objectContaining({
        allowlistSize: 2,
      }),
    });
    // Raw org IDs MUST NOT be embedded in the breadcrumb payload (they are
    // tenant identifiers; size-only signal is sufficient to catch a typo-flip).
    const [crumbData] = addBreadcrumbSpy.mock.calls[0]!;
    const payload = JSON.stringify(crumbData);
    expect(payload).not.toContain("org-jikigai");
    expect(payload).not.toContain("org-other");
  });
});
