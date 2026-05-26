/**
 * Phase 4 (#4229) — Boot-time Sentry breadcrumb for the
 * team-workspace-invite feature gate (single-control via Flagsmith).
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
  it("no-op when NODE_ENV != production (even if flag ON)", async () => {
    mutableEnv.NODE_ENV = "development";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    await emitTeamWorkspaceInviteBootBreadcrumb();
    expect(addBreadcrumbSpy).not.toHaveBeenCalled();
  });

  it("no-op in production when flag OFF", async () => {
    mutableEnv.NODE_ENV = "production";
    delete process.env.FLAG_TEAM_WORKSPACE_INVITE;
    await emitTeamWorkspaceInviteBootBreadcrumb();
    expect(addBreadcrumbSpy).not.toHaveBeenCalled();
  });

  it("emits breadcrumb in production when flag ON", async () => {
    mutableEnv.NODE_ENV = "production";
    process.env.FLAG_TEAM_WORKSPACE_INVITE = "1";
    await emitTeamWorkspaceInviteBootBreadcrumb();
    expect(addBreadcrumbSpy).toHaveBeenCalledTimes(1);
    const [crumb] = addBreadcrumbSpy.mock.calls[0]!;
    expect(crumb).toMatchObject({
      category: "feature-flag",
      level: "info",
      message: "team-workspace-invite single-control gate ON in production",
    });
  });
});
