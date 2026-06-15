import { describe, it, expect, vi, beforeEach } from "vitest";

// Concurrency hardening for `realGraftRepoClone` (review PR #4890 follow-up):
// two cold dispatches for the SAME user can both observe no `.git` and run the
// graft concurrently against the shared `workspacePath`. The fix is a per-attempt
// unique temp dir (so cleanup/clone don't collide) plus a pre-move `.git`
// re-check (so the loser no-ops instead of `rename`-ing onto a populated `.git`).
// These tests mock fs + git so the decision logic is covered without real git/fs.

const {
  mockExistsSync,
  mockGitWithInstallationAuth,
  mockReaddir,
  mockCp,
  mockRename,
  mockRm,
  mockMkdir,
} = vi.hoisted(() => ({
  mockExistsSync: vi.fn(),
  mockGitWithInstallationAuth: vi.fn(),
  mockReaddir: vi.fn(),
  mockCp: vi.fn(),
  mockRename: vi.fn(),
  mockRm: vi.fn(),
  mockMkdir: vi.fn(),
}));

vi.mock("node:fs", () => ({ existsSync: mockExistsSync }));
vi.mock("node:fs/promises", () => ({
  readdir: mockReaddir,
  cp: mockCp,
  rename: mockRename,
  rm: mockRm,
  mkdir: mockMkdir,
}));
vi.mock("@/server/git-auth", () => ({
  gitWithInstallationAuth: mockGitWithInstallationAuth,
}));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));
vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));

import { realGraftRepoClone } from "@/server/ensure-workspace-repo";

const WS = "/workspaces/ws-uuid";
const REPO = "https://github.com/acme/widget";

beforeEach(() => {
  vi.clearAllMocks();
  mockGitWithInstallationAuth.mockResolvedValue(undefined);
  mockReaddir.mockResolvedValue([".git", "knowledge-base"]);
  mockCp.mockResolvedValue(undefined);
  mockRename.mockResolvedValue(undefined);
  mockRm.mockResolvedValue(undefined);
  mockMkdir.mockResolvedValue(undefined);
});

describe("realGraftRepoClone concurrency hardening", () => {
  // Re-provision into a workspace dir that does NOT yet exist on disk (post
  // host/sandbox reclaim). The clone targets <ws>/.ensure-repo-tmp-<uuid>, so
  // the parent <ws> MUST exist first — git clone creates the leaf, not missing
  // parents. RED on origin/main: realGraftRepoClone never mkdir's <ws>.
  it("creates the workspace dir (recursive) BEFORE cloning", async () => {
    mockExistsSync.mockReturnValue(false);
    await realGraftRepoClone(WS, REPO, 123);
    expect(mockMkdir).toHaveBeenCalledWith(WS, { recursive: true });
    // ordering: mkdir must precede the clone (a mkdir after the clone is useless)
    expect(mockMkdir.mock.invocationCallOrder[0]).toBeLessThan(
      mockGitWithInstallationAuth.mock.invocationCallOrder[0],
    );
  });

  it("clones into a UNIQUE per-attempt temp dir (not the fixed .ensure-repo-tmp)", async () => {
    mockExistsSync.mockReturnValue(false);
    await realGraftRepoClone(WS, REPO, 123);

    const cloneArgv = mockGitWithInstallationAuth.mock.calls[0][0] as string[];
    const tmpArg = cloneArgv[cloneArgv.length - 1];
    // Unique suffix: `<ws>/.ensure-repo-tmp-<uuid>`, never the bare shared name.
    expect(tmpArg).toMatch(
      /\/\.ensure-repo-tmp-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
    expect(tmpArg).not.toBe(`${WS}/.ensure-repo-tmp`);
  });

  it("two concurrent grafts use DISTINCT temp dirs", async () => {
    mockExistsSync.mockReturnValue(false);
    await Promise.all([
      realGraftRepoClone(WS, REPO, 123),
      realGraftRepoClone(WS, REPO, 123),
    ]);
    const tmpA = (mockGitWithInstallationAuth.mock.calls[0][0] as string[]).at(-1);
    const tmpB = (mockGitWithInstallationAuth.mock.calls[1][0] as string[]).at(-1);
    expect(tmpA).not.toBe(tmpB);
  });

  it("skips the .git rename when a concurrent attempt grafted first (no ENOTEMPTY)", async () => {
    // `.git` is absent at the top-level guard but APPEARS by the pre-move
    // re-check (the winning concurrent attempt grafted while this one cloned).
    mockExistsSync.mockReturnValue(true);
    await realGraftRepoClone(WS, REPO, 123);
    expect(mockRename).not.toHaveBeenCalled();
    // The loser still cleans up its own unique temp dir.
    expect(mockRm).toHaveBeenCalledTimes(1);
  });

  it("moves .git last when no concurrent winner exists", async () => {
    mockExistsSync.mockReturnValue(false);
    await realGraftRepoClone(WS, REPO, 123);
    expect(mockRename).toHaveBeenCalledTimes(1);
    const [src, dest] = mockRename.mock.calls[0];
    expect(src).toMatch(/\/\.ensure-repo-tmp-.+\/\.git$/);
    expect(dest).toBe(`${WS}/.git`);
  });

  it("cleans up the temp dir even when the clone fails", async () => {
    mockExistsSync.mockReturnValue(false);
    mockGitWithInstallationAuth.mockRejectedValueOnce(new Error("clone boom"));
    await expect(realGraftRepoClone(WS, REPO, 123)).rejects.toThrow("clone boom");
    expect(mockRm).toHaveBeenCalledTimes(1);
    expect(mockRename).not.toHaveBeenCalled();
  });
});
