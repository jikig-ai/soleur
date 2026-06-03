import { describe, it, expect, vi, beforeEach } from "vitest";

// Item 2 — session-start ensure-repo self-heal. Generic per-user/repo,
// idempotent, fail-soft. Detects "connected but not cloned" and repairs by
// grafting a fresh authed clone's .git onto the existing workspace dir, OR
// no-ops when already the connected repo / not connected. Token NEVER logged.

const {
  mockExistsSync,
  mockExecFileAsync,
  mockGitWithInstallationAuth,
  mockGraftRepoClone,
  mockReportSilentFallback,
  mockLogInfo,
} = vi.hoisted(() => ({
  mockExistsSync: vi.fn(),
  mockExecFileAsync: vi.fn(),
  mockGitWithInstallationAuth: vi.fn(),
  mockGraftRepoClone: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockLogInfo: vi.fn(),
}));

vi.mock("node:fs", () => ({ existsSync: mockExistsSync }));
vi.mock("@/server/git-auth", () => ({
  gitWithInstallationAuth: mockGitWithInstallationAuth,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));
vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ info: mockLogInfo, warn: vi.fn(), error: vi.fn() }),
}));

import {
  ensureWorkspaceRepoCloned,
  __setGraftForTests,
} from "@/server/ensure-workspace-repo";

const REPO = "https://github.com/acme/widget";
const WS = "/workspaces/ws-uuid";

beforeEach(() => {
  vi.clearAllMocks();
  // Inject the graft/clone mechanic so orchestration tests don't touch real git/fs.
  __setGraftForTests(mockGraftRepoClone);
  mockGraftRepoClone.mockResolvedValue(undefined);
});

describe("ensureWorkspaceRepoCloned", () => {
  it("not connected (installationId null) → no-op, no error, no graft", async () => {
    await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: null,
      repoUrl: REPO,
    });
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
    expect(mockExistsSync).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("not connected (repoUrl empty) → no-op", async () => {
    await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: null,
    });
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
  });

  it("no .git → clones the connected repo exactly once", async () => {
    mockExistsSync.mockReturnValue(false);
    await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: REPO,
    });
    expect(mockGraftRepoClone).toHaveBeenCalledTimes(1);
    expect(mockGraftRepoClone).toHaveBeenCalledWith(WS, REPO, 123);
  });

  it("already cloned + origin matches → no-op (graft NOT called)", async () => {
    mockExistsSync.mockReturnValue(true);
    mockExecFileAsync.mockResolvedValue({ stdout: `${REPO}.git\n`, stderr: "" });
    __setExecForTests(mockExecFileAsync);
    await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: REPO,
    });
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
  });

  it("already has .git but origin mismatch → repairs (graft called once)", async () => {
    mockExistsSync.mockReturnValue(true);
    mockExecFileAsync.mockResolvedValue({
      stdout: "https://github.com/someone-else/other\n",
      stderr: "",
    });
    __setExecForTests(mockExecFileAsync);
    await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: REPO,
    });
    expect(mockGraftRepoClone).toHaveBeenCalledTimes(1);
  });

  it("clone failure → reportSilentFallback once AND does NOT throw (graceful degrade)", async () => {
    mockExistsSync.mockReturnValue(false);
    mockGraftRepoClone.mockRejectedValue(new Error("clone boom: token ghs_SECRET"));
    await expect(
      ensureWorkspaceRepoCloned({
        userId: "u1",
        workspacePath: WS,
        installationId: 123,
        repoUrl: REPO,
      }),
    ).resolves.toBeUndefined();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [, ctx] = mockReportSilentFallback.mock.calls[0];
    expect(ctx).toMatchObject({ feature: "ensure-workspace-repo" });
  });

  it("token never appears in any log/Sentry payload arg", async () => {
    mockExistsSync.mockReturnValue(false);
    mockGraftRepoClone.mockResolvedValue(undefined);
    await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: REPO,
    });
    const allArgs = JSON.stringify([
      ...mockLogInfo.mock.calls,
      ...mockReportSilentFallback.mock.calls,
    ]);
    expect(allArgs).not.toMatch(/ghs_|x-access-token|GIT_INSTALLATION_TOKEN/);
  });
});

// Helper-injection seam for the exec boundary (declared after import for hoist clarity).
import { __setExecForTests } from "@/server/ensure-workspace-repo";
