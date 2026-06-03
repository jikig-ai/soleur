import { describe, it, expect, vi, beforeEach } from "vitest";

// Item 2 — session-start ensure-repo self-heal. Conservative + brand-safe
// (review PR #4890): heals ONLY the "no .git at all" symptom; NEVER touches an
// existing .git (so it cannot destroy un-pushed work, a Start-Fresh repo, or a
// repo the user intentionally connected). Generic per-user/repo, idempotent,
// fail-soft, token never logged.

const {
  mockExistsSync,
  mockGraftRepoClone,
  mockReportSilentFallback,
  mockLogInfo,
} = vi.hoisted(() => ({
  mockExistsSync: vi.fn(),
  mockGraftRepoClone: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockLogInfo: vi.fn(),
}));

vi.mock("node:fs", () => ({ existsSync: mockExistsSync }));
vi.mock("@/server/git-auth", () => ({ gitWithInstallationAuth: vi.fn() }));
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
  __setGraftForTests(mockGraftRepoClone);
  mockGraftRepoClone.mockResolvedValue(undefined);
});

describe("ensureWorkspaceRepoCloned", () => {
  it("not connected (installationId null) → no-op", async () => {
    await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: null, repoUrl: REPO });
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
    expect(mockExistsSync).not.toHaveBeenCalled();
  });

  it("not connected (repoUrl empty) → no-op", async () => {
    await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: null });
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
  });

  it("no .git → clones the connected repo exactly once", async () => {
    mockExistsSync.mockReturnValue(false);
    await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(mockGraftRepoClone).toHaveBeenCalledTimes(1);
    expect(mockGraftRepoClone).toHaveBeenCalledWith(WS, REPO, 123);
  });

  it("ANY existing .git → no-op (never destroys an existing repo: Start-Fresh, already-cloned, or mismatched origin)", async () => {
    mockExistsSync.mockReturnValue(true);
    await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
  });

  it("non-github / malformed repo_url → skip + Sentry, no clone (argv/format guard)", async () => {
    mockExistsSync.mockReturnValue(false);
    await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: "https://evil.example.com/x/y --upload-pack=evil",
    });
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "ensure-workspace-repo", op: "validate-repo-url" }),
    );
  });

  it("clone failure → reportSilentFallback once AND does NOT throw (graceful degrade)", async () => {
    mockExistsSync.mockReturnValue(false);
    mockGraftRepoClone.mockRejectedValue(new Error("clone boom: token ghs_SECRET"));
    await expect(
      ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO }),
    ).resolves.toBeUndefined();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "ensure-workspace-repo",
      op: "clone",
    });
  });

  it("token never appears in any log/Sentry payload arg — success AND failure paths", async () => {
    // success path
    mockExistsSync.mockReturnValue(false);
    await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    // failure path with a token-shaped error message
    mockGraftRepoClone.mockRejectedValueOnce(new Error("fatal: ghs_aaaaaaaaaaaaaaaaaaaa x-access-token"));
    await ensureWorkspaceRepoCloned({ userId: "u2", workspacePath: WS, installationId: 9, repoUrl: REPO });
    // The Sentry-extra payloads we control must never carry the token. (The raw
    // err object is passed positionally; our structured `extra` is token-free.)
    const ctxArgs = JSON.stringify([
      ...mockLogInfo.mock.calls,
      ...mockReportSilentFallback.mock.calls.map((c) => c[1]),
    ]);
    expect(ctxArgs).not.toMatch(/ghs_|x-access-token|GIT_INSTALLATION_TOKEN/);
  });
});
