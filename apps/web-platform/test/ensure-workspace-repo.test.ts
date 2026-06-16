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

  // #5340 / #5240 item #2 — the return type widened from `void` to a typed
  // `ReprovisionOutcome` ("failed" | "ok") so the cc reconnect path can thread
  // the recovery result to the post-recovery-failure honest message. The fail-
  // soft posture is unchanged (still never throws); only the return is added.
  // "ok" folds every benign exit (not-connected, .git-present, skipped-bad-url,
  // cloned); "failed" is ONLY the genuine clone-catch.
  it("not connected → returns 'ok' (benign, nothing to ensure)", async () => {
    const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: null, repoUrl: REPO });
    expect(out).toBe("ok");
  });

  it("ANY existing .git → returns 'ok' (benign no-op)", async () => {
    mockExistsSync.mockReturnValue(true);
    const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(out).toBe("ok");
  });

  it("malformed repo_url → returns 'ok' (benign skip, not a recovery failure)", async () => {
    mockExistsSync.mockReturnValue(false);
    const out = await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: "https://evil.example.com/x/y --upload-pack=evil",
    });
    expect(out).toBe("ok");
  });

  it("successful clone → returns 'ok'", async () => {
    mockExistsSync.mockReturnValue(false);
    const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(out).toBe("ok");
  });

  it("clone failure (catch) → returns 'failed' (the only non-benign outcome)", async () => {
    mockExistsSync.mockReturnValue(false);
    mockGraftRepoClone.mockRejectedValue(new Error("clone boom"));
    const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(out).toBe("failed");
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

  it("success breadcrumb keeps action:'cloned' but drops the raw userId key (item 3 — clears userid-bypass-lint)", async () => {
    mockExistsSync.mockReturnValue(false);
    await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(mockLogInfo).toHaveBeenCalledTimes(1);
    const firstArg = mockLogInfo.mock.calls[0][0];
    expect(firstArg).toMatchObject({ action: "cloned" });
    // The direct logger.info site must NOT carry a raw `userId` key — pino's
    // formatters.log hashes top-level userId at runtime, but the advisory
    // userid-bypass-lint guard scans SOURCE for direct logger({ userId }).
    expect(firstArg).not.toHaveProperty("userId");
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
    // Fail-soft: resolves (never throws). The resolved value is the typed
    // "failed" outcome (was `void` pre-#5340) — covered by the dedicated
    // outcome test above; here we only assert the no-throw posture.
    await expect(
      ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO }),
    ).resolves.toBe("failed");
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
