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
  mockReportRepoCloneFailed,
  mockLogInfo,
  mockLogWarn,
  mockIsValid,
  mockIsEmptyCorrupt,
  mockProbeShape,
  mockRm,
  mockIsGitDataStoreEnabled,
  mockFetchFromGitData,
  mockResolveWorktreeId,
  mockLocalGit,
  mockSeedWorktreeConfig,
} = vi.hoisted(() => ({
  mockExistsSync: vi.fn(),
  mockGraftRepoClone: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockReportRepoCloneFailed: vi.fn(),
  mockLogInfo: vi.fn(),
  mockLogWarn: vi.fn(),
  mockIsValid: vi.fn(),
  mockIsEmptyCorrupt: vi.fn(),
  mockProbeShape: vi.fn(),
  mockRm: vi.fn(),
  // Sub-PR 3.D — clone-from-git-data read-source overlay seams.
  mockIsGitDataStoreEnabled: vi.fn(),
  mockFetchFromGitData: vi.fn(),
  mockResolveWorktreeId: vi.fn(),
  mockLocalGit: vi.fn(),
  mockSeedWorktreeConfig: vi.fn(),
}));

vi.mock("node:fs", () => ({ existsSync: mockExistsSync }));
// `rm` (corrupt-`.git` removal) is mocked so the validity-aware early-return is
// driven without touching disk; the real fingerprint/rm safety is covered by
// test/server/git-worktree-validity.test.ts.
vi.mock("node:fs/promises", async (orig) => {
  const actual = (await orig()) as Record<string, unknown>;
  return { ...actual, rm: mockRm };
});
// 2026-06-19 — validity probes mocked so the orchestration decision (valid →
// no-op, empty-corrupt → rm+clone, populated-broken → honest-block) is tested
// independently of the fs-level fingerprint logic.
vi.mock("@/server/git-worktree-validity", () => ({
  isValidGitWorkTree: mockIsValid,
  isEmptyCorruptGitDir: mockIsEmptyCorrupt,
  probeGitWorktreeShape: mockProbeShape,
  // Pure function of the shape — provide the real predicate so the heal gates on
  // the (mocked) shape the test sets, no separate spy to keep in sync.
  isStrandingFilePointer: (s: { kind: string; gitdirEscapesWorkspace?: boolean }) =>
    s.kind === "file-pointer" && s.gitdirEscapesWorkspace !== false,
}));
vi.mock("@/server/workspace-permission-lock", () => ({
  withWorkspacePermissionLock: (_p: string, fn: () => unknown) => fn(),
}));
vi.mock("@/server/git-auth", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/git-auth")>()),
  gitWithInstallationAuth: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));
// #5733 D0 — the loud repo_clone_failed reporter is wired into the clone catch.
vi.mock("@/server/repo-resolver-divergence", () => ({
  reportRepoCloneFailed: mockReportRepoCloneFailed,
}));
vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ info: mockLogInfo, warn: mockLogWarn, error: vi.fn() }),
}));
// Sub-PR 3.D — the clone-from-git-data overlay: flag gate, membership-gated
// fetch into refs/remotes/git-data/*, and the per-user worktree id resolver.
vi.mock("@/server/workspace-resolver", () => ({
  isGitDataStoreEnabled: mockIsGitDataStoreEnabled,
}));
vi.mock("@/server/git-data-client", () => ({
  fetchFromGitData: mockFetchFromGitData,
}));
vi.mock("@/server/worktree-write-lease", () => ({
  resolveWorktreeId: mockResolveWorktreeId,
}));
// #4826 — the host-side worktree-config re-seed. Spied so the boot path's calls are
// assertable without touching real git (the seeder's behavior is unit-tested in
// worktree-config-seed.test.ts).
vi.mock("@/server/worktree-config-seed", () => ({
  seedWorktreeConfig: mockSeedWorktreeConfig,
}));

import {
  ensureWorkspaceRepoCloned,
  __setGraftForTests,
  __setLocalGitForTests,
  isFirstSessionStoreMiss,
} from "@/server/ensure-workspace-repo";

const REPO = "https://github.com/acme/widget";
const WS = "/workspaces/ws-uuid";

beforeEach(() => {
  vi.clearAllMocks();
  __setGraftForTests(mockGraftRepoClone);
  mockGraftRepoClone.mockResolvedValue(undefined);
  // Default: a `.git` (when existsSync says present) is neither valid nor the
  // empty-corrupt fingerprint; absent-`.git` tests set existsSync=false so these
  // are not consulted. Per-test overrides set the validity shape under test.
  mockIsValid.mockReturnValue(false);
  mockIsEmptyCorrupt.mockReturnValue(false);
  // Default shape is NOT a file-pointer, so the #5733 pointer-heal branch stays
  // dormant for the legacy cases (which drive behavior via mockIsValid /
  // mockIsEmptyCorrupt). The file-pointer test below overrides per-call.
  mockProbeShape.mockReturnValue({ kind: "dir-invalid" });
  mockRm.mockResolvedValue(undefined);
  // Sub-PR 3.D overlay seams. Flag OFF by default so the legacy cases above are
  // wholly unaffected (overlay dormant). Local git seam resolves benignly; the
  // per-test overrides drive the overlay behavior under test.
  __setLocalGitForTests(mockLocalGit);
  mockIsGitDataStoreEnabled.mockReturnValue(false);
  mockFetchFromGitData.mockResolvedValue(undefined);
  mockResolveWorktreeId.mockImplementation((userId: string) => `wt-${userId}`);
  mockLocalGit.mockResolvedValue({ stdout: "" });
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

  it("VALID existing .git → returns 'ok' (benign no-op; never touched)", async () => {
    mockExistsSync.mockReturnValue(true);
    mockIsValid.mockReturnValue(true);
    const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(out).toBe("ok");
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
    expect(mockRm).not.toHaveBeenCalled();
  });

  it("empty-corrupt .git (fingerprint match) → rm under lock + re-clone → 'ok'", async () => {
    mockExistsSync.mockReturnValue(true);
    mockIsValid.mockReturnValue(false); // invalid
    mockIsEmptyCorrupt.mockReturnValue(true); // the ONLY rm-authorized shape
    const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(mockRm).toHaveBeenCalledTimes(1); // corrupt .git removed
    expect(mockGraftRepoClone).toHaveBeenCalledTimes(1); // then re-cloned
    expect(out).toBe("ok");
  });

  it("populated-but-broken .git (invalid, NOT empty-corrupt) → honest-block 'failed', NEVER rm/clone (F2)", async () => {
    mockExistsSync.mockReturnValue(true);
    mockIsValid.mockReturnValue(false); // invalid
    mockIsEmptyCorrupt.mockReturnValue(false); // does NOT match the rm fingerprint
    const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(out).toBe("failed");
    expect(mockRm).not.toHaveBeenCalled(); // never destroy a populated/EACCES/gitdir-file .git
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "ensure-workspace-repo", op: "corrupt-worktree-block" }),
    );
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

  it("#5733 D0: clone failure ALSO emits the loud repo_clone_failed reporter (every caller) with the basename-derived workspace id + the raw reason", async () => {
    mockExistsSync.mockReturnValue(false);
    mockGraftRepoClone.mockRejectedValue(new Error("clone boom /workspaces/ws-uuid/.t"));
    const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(out).toBe("failed");
    expect(mockReportRepoCloneFailed).toHaveBeenCalledTimes(1);
    expect(mockReportRepoCloneFailed).toHaveBeenCalledWith({
      userId: "u1",
      activeWorkspaceId: "ws-uuid", // basename(WS) — sanitized/hashed inside the reporter
      reason: "clone boom /workspaces/ws-uuid/.t",
    });
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

  it("VALID existing .git → no-op (never destroys a real repo: Start-Fresh, already-cloned, or mismatched origin)", async () => {
    mockExistsSync.mockReturnValue(true);
    mockIsValid.mockReturnValue(true);
    mockProbeShape.mockReturnValue({ kind: "dir-valid" });
    await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
    expect(mockRm).not.toHaveBeenCalled();
    // #4826 — an existing valid workspace must STILL be re-seeded every boot, so a
    // workspace provisioned before the seed shipped stops wedging in-sandbox worktree
    // creation. This is the fix for the "fresh session, existing workspace" failure.
    expect(mockSeedWorktreeConfig).toHaveBeenCalledWith(WS);
  });

  // #5733 — a `.git` FILE pointer at a workspace ROOT is a stale gitdir pointer
  // (never a legit linked-worktree for a personal workspace). It passes
  // isValidGitWorkTree (lstat) but strands the agent's in-bwrap `git rev-parse`.
  // The pointer-heal removes the single FILE (NOT a recursive dir rm) and
  // re-clones a self-contained repo from origin HEAD.
  it("stale gitdir-pointer .git FILE → unlink the pointer + re-clone → 'ok'", async () => {
    mockProbeShape.mockReturnValue({
      kind: "file-pointer",
      gitdirTarget: "/workspaces/other/.git/worktrees/x",
      gitdirEscapesWorkspace: true,
    });
    // After the pointer is removed the tree is .git-absent → graft clones.
    mockExistsSync.mockReturnValue(false);
    mockIsValid.mockReturnValue(false);

    const out = await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: REPO,
    });

    expect(out).toBe("ok");
    // The pointer FILE was unlinked (force, NOT recursive) before re-clone.
    expect(mockRm).toHaveBeenCalledTimes(1);
    expect(mockRm).toHaveBeenCalledWith(`${WS}/.git`, { force: true });
    expect(mockGraftRepoClone).toHaveBeenCalledTimes(1);
    expect(mockGraftRepoClone).toHaveBeenCalledWith(WS, REPO, 123);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "ensure-workspace-repo",
        op: "gitdir-pointer-reclone",
      }),
    );
  });

  it("NON-escaping in-workspace `.git` pointer → NOT a strand → left untouched (no unlink, no clone)", async () => {
    // A pointer whose gitdir target stays inside the workspace is readable
    // in-sandbox and does NOT strand → the heal must not fire (no data risk).
    mockProbeShape.mockReturnValue({
      kind: "file-pointer",
      gitdirTarget: "./.git-real",
      gitdirEscapesWorkspace: false,
    });
    mockExistsSync.mockReturnValue(true);
    mockIsValid.mockReturnValue(true); // a non-escaping pointer is lstat-valid → no-op gate returns "ok"

    const out = await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: REPO,
    });

    expect(out).toBe("ok");
    expect(mockRm).not.toHaveBeenCalled(); // not stranding → never unlinked
    expect(mockGraftRepoClone).not.toHaveBeenCalled();
  });

  it("file-pointer heal: a racer that grafts a valid .git mid-lock → no unlink, no double-clone", async () => {
    // First probe (gate) sees a file-pointer; the lock re-check sees a valid dir
    // (a racer grafted) → the unlink is skipped.
    mockProbeShape
      .mockReturnValueOnce({ kind: "file-pointer", gitdirEscapesWorkspace: true })
      .mockReturnValue({ kind: "dir-valid" });
    mockExistsSync.mockReturnValue(true);
    mockIsValid.mockReturnValue(true); // racer's valid .git → clone no-op

    const out = await ensureWorkspaceRepoCloned({
      userId: "u1",
      workspacePath: WS,
      installationId: 123,
      repoUrl: REPO,
    });

    expect(out).toBe("ok");
    expect(mockRm).not.toHaveBeenCalled(); // re-check under lock saw a valid dir
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

  // -------------------------------------------------------------------------
  // Sub-PR 3.D (#5274 Phase 3, ADR-068) — clone-from-git-data read-source
  // overlay. Rehydration = clone(GitHub) → overlay(git-data). git-data ⊇ GitHub
  // origin in committed-ref completeness, so after a FRESH graft we overlay the
  // user's latest committed tip from refs/remotes/git-data/<primary>.
  //
  // SAFETY INVARIANT (the CTO's proof): the overlay/reset is reachable ONLY on
  // the fresh-graft path, which sits AFTER the early-return
  // `if (isValidGitWorkTree) return "ok"`. So any LIVE worktree that could hold
  // local-only commits returns BEFORE the overlay — by construction zero
  // local-only commits exist at the reset point.
  // -------------------------------------------------------------------------
  describe("clone-from-git-data overlay", () => {
    const primaryRef = (b: string) => `refs/remotes/git-data/${b}`;

    // (a) LIVE worktree → early-return fires FIRST → no fetch, no reset. Proves
    // the overlay can never discard local-only commits from a live worktree.
    it("VALID (live) worktree → early-return before overlay: NO fetch, NO reset (no discard of local-only commits)", async () => {
      mockIsGitDataStoreEnabled.mockReturnValue(true); // flag ON — overlay eligible
      mockExistsSync.mockReturnValue(true);
      mockIsValid.mockReturnValue(true); // live worktree → early return "ok"
      const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
      expect(out).toBe("ok");
      expect(mockGraftRepoClone).not.toHaveBeenCalled();
      expect(mockFetchFromGitData).not.toHaveBeenCalled();
      expect(mockLocalGit).not.toHaveBeenCalled(); // no rev-parse / show-ref / reset
    });

    // (b) fresh-graft + flag ON + ref PRESENT → fetch with derived ids, then
    // reset --hard onto the git-data tip.
    it("fresh graft, flag ON, git-data ref PRESENT → fetch(derived ids) + reset --hard onto the git-data tip", async () => {
      mockIsGitDataStoreEnabled.mockReturnValue(true);
      mockExistsSync.mockReturnValue(false); // no .git → fresh graft path
      // Gate (line ~208) sees invalid → proceeds; the under-lock re-check sees a
      // now-valid grafted worktree → the reset runs.
      mockIsValid.mockReturnValueOnce(false).mockReturnValue(true);
      mockLocalGit.mockImplementation(async (args: string[]) => {
        if (args[0] === "rev-parse") return { stdout: "main\n" };
        return { stdout: "" }; // show-ref present (resolves) + reset
      });

      const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });

      expect(out).toBe("ok");
      expect(mockGraftRepoClone).toHaveBeenCalledTimes(1);
      // fetch called with the basename-derived workspaceId + resolveWorktreeId(userId).
      expect(mockFetchFromGitData).toHaveBeenCalledTimes(1);
      expect(mockFetchFromGitData).toHaveBeenCalledWith({
        userId: "u1",
        workspaceId: "ws-uuid", // basename(WS)
        worktreeId: "wt-u1", // resolveWorktreeId(userId)
        workspacePath: WS,
      });
      expect(mockResolveWorktreeId).toHaveBeenCalledWith("u1");
      // rev-parse resolved primary, show-ref verified the ref, reset overlaid it.
      expect(mockLocalGit).toHaveBeenCalledWith(["rev-parse", "--abbrev-ref", "HEAD"], WS);
      expect(mockLocalGit).toHaveBeenCalledWith(
        ["show-ref", "--verify", "--quiet", primaryRef("main")],
        WS,
      );
      expect(mockLocalGit).toHaveBeenCalledWith(["reset", "--hard", primaryRef("main")], WS);
    });

    // (c) fresh-graft + flag ON + ref ABSENT (empty git-data / first-ever
    // session) → NO reset; keep the GitHub clone; still "ok".
    it("fresh graft, flag ON, git-data ref ABSENT → NO reset (keep GitHub clone), outcome 'ok'", async () => {
      mockIsGitDataStoreEnabled.mockReturnValue(true);
      mockExistsSync.mockReturnValue(false);
      mockIsValid.mockReturnValueOnce(false).mockReturnValue(true);
      mockLocalGit.mockImplementation(async (args: string[]) => {
        if (args[0] === "rev-parse") return { stdout: "main\n" };
        if (args[0] === "show-ref") throw new Error("ref absent (exit 1)"); // git-data empty
        return { stdout: "" };
      });

      const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });

      expect(out).toBe("ok");
      expect(mockFetchFromGitData).toHaveBeenCalledTimes(1);
      // No reset ran (ref absent → keep the fresh GitHub clone).
      const resetCalls = mockLocalGit.mock.calls.filter((c) => c[0][0] === "reset");
      expect(resetCalls).toHaveLength(0);
    });

    // (d) flag OFF → the overlay is wholly dormant: no fetch, no local git.
    it("flag OFF → NO fetch, NO reset (unchanged pre-3.D behavior)", async () => {
      mockIsGitDataStoreEnabled.mockReturnValue(false);
      mockExistsSync.mockReturnValue(false);
      const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });
      expect(out).toBe("ok");
      expect(mockGraftRepoClone).toHaveBeenCalledTimes(1);
      expect(mockFetchFromGitData).not.toHaveBeenCalled();
      expect(mockLocalGit).not.toHaveBeenCalled();
    });

    // (e) a fetch/overlay error is FAIL-SOFT: outcome still "ok" + mirrored to
    // Sentry via reportSilentFallback (git-data is an overlay, not a hard dep;
    // the GitHub clone is a valid fallback).
    it("fetch/overlay error → still 'ok' + reportSilentFallback (fail-soft; git-data blip must not fail the clone)", async () => {
      mockIsGitDataStoreEnabled.mockReturnValue(true);
      mockExistsSync.mockReturnValue(false);
      mockIsValid.mockReturnValueOnce(false).mockReturnValue(true);
      mockFetchFromGitData.mockRejectedValue(new Error("git-data unreachable"));

      const out = await ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });

      expect(out).toBe("ok"); // fail-soft: the GitHub clone stands
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          feature: "ensure-workspace-repo",
          op: "git-data-overlay",
          extra: { userId: "u1" },
        }),
      );
      // The error was swallowed BEFORE any reset.
      const resetCalls = mockLocalGit.mock.calls.filter((c) => c[0][0] === "reset");
      expect(resetCalls).toHaveLength(0);
    });

    // -----------------------------------------------------------------------
    // #11704 Phase 2 — first-session classification (CTO F5) and the ancestry
    // gate with its rescue branch (CTO F4/F7/F11).
    // -----------------------------------------------------------------------
    const STORE_SHA = "0123456789abcdef0123456789abcdef01234567";
    // CTO F12: a FLAT name. A `soleur/` prefix would let a store head named `soleur` make every
    // later (atomic) push for that user fail on a refname conflict.
    const RESCUE = "soleur-store-tip-0123456789ab";
    const WRAPPER_STDERR =
      "remote: git-data transport: repo does not exist (provision it first): '/srv/x/ws-uuid.git'\n" +
      "fatal: Could not read from remote repository.";
    const execErr = (message: string, code: number | undefined, stderr?: string) =>
      Object.assign(new Error(message), { code, stderr });
    const allLogs = () =>
      JSON.stringify([
        mockLogInfo.mock.calls,
        mockLogWarn.mock.calls,
        mockReportSilentFallback.mock.calls,
      ]);
    const gitCalls = (verb: string) => mockLocalGit.mock.calls.filter((c) => c[0][0] === verb);

    function armOverlay(
      handlers: {
        mergeBase?: () => Promise<{ stdout: string }>;
        branch?: () => Promise<{ stdout: string }>;
        branchRevParse?: () => Promise<{ stdout: string }>;
        // `git rev-parse <dataRef>` (the store tip sha); default is a valid full sha.
        storeTip?: () => Promise<{ stdout: string }>;
        // `git rev-parse HEAD` (the fresh clone tip); default is empty (unresolvable).
        head?: () => Promise<{ stdout: string }>;
      } = {},
    ) {
      mockIsGitDataStoreEnabled.mockReturnValue(true);
      mockExistsSync.mockReturnValue(false);
      mockIsValid.mockReturnValueOnce(false).mockReturnValue(true);
      mockLocalGit.mockImplementation(async (args: string[]) => {
        if (args[0] === "rev-parse" && args[1] === "--abbrev-ref") return { stdout: "main\n" };
        if (args[0] === "rev-parse" && args[1] === primaryRef("main")) {
          return handlers.storeTip ? handlers.storeTip() : { stdout: `${STORE_SHA}\n` };
        }
        if (args[0] === "rev-parse" && args[1] === "HEAD") {
          return handlers.head ? handlers.head() : { stdout: "" };
        }
        if (args[0] === "rev-parse") {
          return handlers.branchRevParse ? handlers.branchRevParse() : { stdout: "" };
        }
        if (args[0] === "merge-base") return handlers.mergeBase ? handlers.mergeBase() : { stdout: "" };
        if (args[0] === "branch") return handlers.branch ? handlers.branch() : { stdout: "" };
        return { stdout: "" }; // show-ref present + reset
      });
    }
    const run = () =>
      ensureWorkspaceRepoCloned({ userId: "u1", workspacePath: WS, installationId: 123, repoUrl: REPO });

    describe("first-session store miss (isFirstSessionStoreMiss)", () => {
      it("code 128 + the wrapper phrase on stderr → info, NOT the level-50 fallback; no reset; no ids in any log", async () => {
        armOverlay();
        mockFetchFromGitData.mockRejectedValue(execErr("Command failed: git fetch", 128, WRAPPER_STDERR));
        const out = await run();
        expect(out).toBe("ok");
        expect(mockReportSilentFallback).not.toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({ op: "git-data-overlay" }),
        );
        expect(mockLogInfo).toHaveBeenCalledWith(
          expect.objectContaining({ action: "git-data-overlay-first-session-miss" }),
          expect.any(String),
        );
        expect(gitCalls("reset")).toHaveLength(0);
        const logs = allLogs();
        expect(logs).not.toContain("u1");
        expect(logs).not.toContain("ws-uuid");
        expect(logs).not.toContain("/srv/x");
      });

      it("a non-miss fetch failure stays level 50", async () => {
        armOverlay();
        mockFetchFromGitData.mockRejectedValue(execErr("git-data unreachable", 128, "ssh: connect to host: Connection timed out"));
        await run();
        expect(mockReportSilentFallback).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({ op: "git-data-overlay" }),
        );
        expect(mockLogInfo).not.toHaveBeenCalledWith(
          expect.objectContaining({ action: "git-data-overlay-first-session-miss" }),
          expect.anything(),
        );
      });

      it("the phrase with a non-128 code stays level 50 (through the overlay)", async () => {
        armOverlay();
        mockFetchFromGitData.mockRejectedValue(execErr("Command failed", 1, WRAPPER_STDERR));
        await run();
        expect(mockReportSilentFallback).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({ op: "git-data-overlay" }),
        );
      });

      it.each([
        ["code 128 + phrase on stderr", execErr("Command failed", 128, WRAPPER_STDERR), true],
        ["code 128 + phrase only in message (no stderr)", execErr(`Command failed\n${WRAPPER_STDERR}`, 128, undefined), true],
        ["code 128 + phrase only in message (empty stderr)", execErr(`Command failed\n${WRAPPER_STDERR}`, 128, ""), true],
        ["code 1 + phrase", execErr("Command failed", 1, WRAPPER_STDERR), false],
        ["code undefined + phrase", execErr("Command failed", undefined, WRAPPER_STDERR), false],
        ["string code '128' + phrase", execErr("Command failed", "128" as unknown as number, WRAPPER_STDERR), false],
        ["code 128 + Permission denied", execErr("Command failed", 128, "git@host: Permission denied (publickey).\nfatal: Could not read from remote repository."), false],
        ["code 128 + phrase text on message but stderr names a different failure", execErr(`Command failed\n${WRAPPER_STDERR}`, 128, "ssh: connect to host: Connection refused"), false],
        // N22: the phrase is matched whole. A bare "does not exist" (or a bare "provision it first")
        // on a code-128 failure is some other fault and must stay level 50.
        ["code 128 + 'does not exist' without the parenthetical", execErr("Command failed", 128, "fatal: '/srv/x/ws-uuid.git' does not exist"), false],
        ["code 128 + 'provision it first' without 'does not exist'", execErr("Command failed", 128, "remote: git-data transport: (provision it first)"), false],
        ["non-object", "does not exist (provision it first)", false],
        ["null", null, false],
      ])("%s → %s", (_n, err, expected) => {
        expect(isFirstSessionStoreMiss(err)).toBe(expected);
      });
    });

    describe("ancestry gate + rescue branch", () => {
      it("store tip descends from the clone tip → merge-base then reset --hard, no rescue branch", async () => {
        armOverlay();
        const out = await run();
        expect(out).toBe("ok");
        expect(mockLocalGit).toHaveBeenCalledWith(["merge-base", "--is-ancestor", "HEAD", primaryRef("main")], WS);
        const verbs = mockLocalGit.mock.calls.map((c) => c[0][0]);
        expect(verbs.indexOf("merge-base")).toBeGreaterThan(-1);
        expect(verbs.indexOf("merge-base")).toBeLessThan(verbs.indexOf("reset"));
        expect(mockLocalGit).toHaveBeenCalledWith(["reset", "--hard", primaryRef("main")], WS);
        expect(gitCalls("branch")).toHaveLength(0);
        expect(mockLogWarn).not.toHaveBeenCalled();
      });

      it("not a descendant (merge-base exit 1) → rescue branch created BEFORE the skip; no reset; warn without ids; no Sentry", async () => {
        armOverlay({ mergeBase: async () => { throw execErr("Command failed", 1, ""); } });
        const out = await run();
        expect(out).toBe("ok");
        // N25: created from the full sha that named it, not from the ref name
        expect(mockLocalGit).toHaveBeenCalledWith(["branch", RESCUE, STORE_SHA], WS);
        expect(gitCalls("reset")).toHaveLength(0);
        const verbs = mockLocalGit.mock.calls.map((c) => c[0][0]);
        expect(verbs.indexOf("merge-base")).toBeLessThan(verbs.indexOf("branch"));
        // the rescue branch is created without -f
        expect(JSON.stringify(gitCalls("branch"))).not.toMatch(/"-f"|"--force"|"-D"|"-M"/);
        expect(mockLogWarn).toHaveBeenCalledTimes(1);
        expect(mockLogWarn).toHaveBeenCalledWith(
          expect.objectContaining({ op: "git-data-overlay-not-descendant" }),
          expect.any(String),
        );
        expect(mockReportSilentFallback).not.toHaveBeenCalled();
        const logs = allLogs();
        expect(logs).not.toContain("u1");
        expect(logs).not.toContain("ws-uuid");
        expect(logs).not.toContain(STORE_SHA.slice(0, 12));
      });

      it("not a descendant and the branch cannot be created → level-50 fallback, NO reset, no skip warn", async () => {
        armOverlay({
          mergeBase: async () => { throw execErr("Command failed", 1, ""); },
          branch: async () => { throw execErr("Command failed", 128, "fatal: cannot lock ref"); },
        });
        const out = await run();
        expect(out).toBe("ok");
        expect(mockReportSilentFallback).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({ op: "git-data-overlay" }),
        );
        expect(gitCalls("reset")).toHaveLength(0);
        expect(mockLogWarn).not.toHaveBeenCalled();
      });

      it("not a descendant and the rescue branch already exists at the same sha → success (skip warn, no fallback)", async () => {
        armOverlay({
          mergeBase: async () => { throw execErr("Command failed", 1, ""); },
          branch: async () => { throw execErr("Command failed", 128, `fatal: a branch named '${RESCUE}' already exists`); },
          branchRevParse: async () => ({ stdout: `${STORE_SHA}\n` }),
        });
        await run();
        expect(mockReportSilentFallback).not.toHaveBeenCalled();
        expect(mockLogWarn).toHaveBeenCalledWith(
          expect.objectContaining({ op: "git-data-overlay-not-descendant" }),
          expect.any(String),
        );
        expect(gitCalls("reset")).toHaveLength(0);
      });

      it("rescue branch exists at a DIFFERENT sha → level-50 fallback, NO reset", async () => {
        armOverlay({
          mergeBase: async () => { throw execErr("Command failed", 1, ""); },
          branch: async () => { throw execErr("Command failed", 128, "already exists"); },
          branchRevParse: async () => ({ stdout: "ffffffffffffffffffffffffffffffffffffffff\n" }),
        });
        await run();
        expect(mockReportSilentFallback).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({ op: "git-data-overlay" }),
        );
        expect(gitCalls("reset")).toHaveLength(0);
        expect(mockLogWarn).not.toHaveBeenCalled();
      });

      // CTO F14 (amends F4/F7): an INDETERMINATE ancestry result (exit neither 0 nor 1) is not an
      // answer. The store tip is still protected with a best-effort rescue branch, then the ORIGINAL
      // error goes to the level-50 catch; the reset never runs.
      it("merge-base exits 128 → best-effort rescue branch, original error reported once at level 50, no reset", async () => {
        const mbErr = execErr("Command failed", 128, "fatal: Not a valid object name");
        armOverlay({ mergeBase: async () => { throw mbErr; } });
        const out = await run();
        expect(out).toBe("ok");
        expect(mockLocalGit).toHaveBeenCalledWith(["branch", RESCUE, STORE_SHA], WS);
        expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
        expect(mockReportSilentFallback).toHaveBeenCalledWith(
          mbErr, // the ORIGINAL error object, not the rescue's
          expect.objectContaining({ op: "git-data-overlay" }),
        );
        expect(gitCalls("reset")).toHaveLength(0);
        // ordering: ancestry was asked first, the rescue came after
        const verbs = mockLocalGit.mock.calls.map((c) => c[0][0]);
        expect(verbs.indexOf("merge-base")).toBeLessThan(verbs.indexOf("branch"));
        expect(mockLogWarn).not.toHaveBeenCalled(); // no "skipped" warn: this is the fault path
      });

      it("merge-base exits 128 and the rescue branch ALSO fails → the secondary error is swallowed; the original is reported once; no reset", async () => {
        const mbErr = execErr("Command failed", 128, "fatal: Not a valid object name");
        armOverlay({
          mergeBase: async () => { throw mbErr; },
          branch: async () => { throw execErr("Command failed", 128, "fatal: not a valid object name: missing"); },
          branchRevParse: async () => { throw execErr("Command failed", 128, "fatal: Needed a single revision"); },
        });
        const out = await run();
        expect(out).toBe("ok");
        expect(gitCalls("branch")).toHaveLength(1);
        expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
        expect(mockReportSilentFallback).toHaveBeenCalledWith(
          mbErr,
          expect.objectContaining({ op: "git-data-overlay" }),
        );
        expect(gitCalls("reset")).toHaveLength(0);
      });

      it("merge-base exits 128 and the store tip does not resolve to a commit id → no branch call, original error reported, no reset", async () => {
        const mbErr = execErr("Command failed", 128, "fatal: Not a valid object name");
        armOverlay({ mergeBase: async () => { throw mbErr; }, storeTip: async () => ({ stdout: "zzz\n" }) });
        await run();
        expect(gitCalls("branch")).toHaveLength(0);
        expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
        expect(mockReportSilentFallback).toHaveBeenCalledWith(mbErr, expect.objectContaining({ op: "git-data-overlay" }));
        expect(gitCalls("reset")).toHaveLength(0);
      });

      // N24: the `^[0-9a-f]{40,64}$` guard on the resolved store tip. Replacing it with `true`
      // would build a branch name from garbage.
      it.each([
        ["empty", ""],
        ["non-hex", "zzz"],
        ["too short", "0123456789abcdef"],
        ["upper-case hex", "0123456789ABCDEF0123456789ABCDEF01234567"],
        ["a symbolic name", "refs/remotes/git-data/main"],
      ])("not a descendant and rev-parse of the store tip returns %s → level-50 fallback, NO branch call, NO reset, no skip warn", async (_n, out) => {
        armOverlay({
          mergeBase: async () => { throw execErr("Command failed", 1, ""); },
          storeTip: async () => ({ stdout: `${out}\n` }),
        });
        await run();
        expect(gitCalls("branch")).toHaveLength(0);
        expect(gitCalls("reset")).toHaveLength(0);
        expect(mockReportSilentFallback).toHaveBeenCalledWith(
          expect.anything(),
          expect.objectContaining({ op: "git-data-overlay" }),
        );
        expect(mockLogWarn).not.toHaveBeenCalled();
      });

      // N27: a second racer whose clone already sits at the store tip must not `reset --hard`
      // (that would wipe uncommitted edits the first racer's session already made).
      it("descends and HEAD already equals the store tip → NO reset (and no rescue branch)", async () => {
        armOverlay({ head: async () => ({ stdout: `${STORE_SHA}\n` }) });
        const out = await run();
        expect(out).toBe("ok");
        expect(mockLocalGit).toHaveBeenCalledWith(["rev-parse", "HEAD"], WS);
        expect(gitCalls("reset")).toHaveLength(0);
        expect(gitCalls("branch")).toHaveLength(0);
        expect(mockReportSilentFallback).not.toHaveBeenCalled();
        expect(mockLogWarn).not.toHaveBeenCalled();
      });

      it("descends and HEAD differs from the store tip → reset --hard still runs (positive control for the equality skip)", async () => {
        armOverlay({ head: async () => ({ stdout: "ffffffffffffffffffffffffffffffffffffffff\n" }) });
        await run();
        expect(mockLocalGit).toHaveBeenCalledWith(["reset", "--hard", primaryRef("main")], WS);
      });

      it("descends and `rev-parse HEAD` fails → the optimisation is skipped, reset --hard still runs", async () => {
        armOverlay({ head: async () => { throw execErr("Command failed", 128, "fatal: bad revision"); } });
        await run();
        expect(mockLocalGit).toHaveBeenCalledWith(["reset", "--hard", primaryRef("main")], WS);
        expect(mockReportSilentFallback).not.toHaveBeenCalled();
      });
    });
  });
});
