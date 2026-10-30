/**
 * Push Branch Tool Tests (Phase 4, #1929)
 *
 * Tests the github_push_branch handler function:
 * - Branch name validation (rejects main/master/default)
 * - Force-push blocking
 * - Branch format validation (git ref format rules)
 * - Delegates authenticated push to `gitWithInstallationAuth` (git-auth.ts)
 * - Git author configuration
 */
import { describe, test, expect, vi, beforeEach } from "vitest";

// Mock child_process so the `git config user.name/user.email` calls inside
// push-branch don't try to run real git. `gitWithInstallationAuth` is
// mocked separately at the module boundary — it owns all credential
// lifecycle testing (see test/git-auth.test.ts).
const { mockExecFileSync, mockGitWithAuth } = vi.hoisted(() => ({
  mockExecFileSync: vi.fn(),
  mockGitWithAuth: vi.fn(),
}));

vi.mock("child_process", () => ({
  execFileSync: mockExecFileSync,
}));

vi.mock("../server/git-auth", () => ({
  gitWithInstallationAuth: mockGitWithAuth,
}));

vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

import {
  rejectProtectedBranch,
  PROTECTED_BRANCHES,
  pushBranch,
} from "../server/push-branch";

describe("rejectProtectedBranch", () => {
  test("rejects 'main'", () => {
    expect(() => rejectProtectedBranch("main")).toThrow(/protected/i);
  });

  test("rejects 'master'", () => {
    expect(() => rejectProtectedBranch("master")).toThrow(/protected/i);
  });

  test("rejects custom default branch", () => {
    expect(() => rejectProtectedBranch("develop", "develop")).toThrow(/protected/i);
  });

  test("allows feature branches", () => {
    expect(() => rejectProtectedBranch("feat-ci-cd")).not.toThrow();
  });

  test("allows branches with slashes", () => {
    expect(() => rejectProtectedBranch("fix/bug-123")).not.toThrow();
  });

  test("PROTECTED_BRANCHES includes main and master", () => {
    expect(PROTECTED_BRANCHES).toContain("main");
    expect(PROTECTED_BRANCHES).toContain("master");
  });
});

describe("pushBranch", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockExecFileSync.mockReturnValue(Buffer.from(""));
    mockGitWithAuth.mockResolvedValue(Buffer.from(""));
  });

  test("rejects force-push unconditionally", async () => {
    await expect(
      pushBranch({
        installationId: 12345,
        owner: "alice",
        repo: "my-repo",
        workspacePath: "/tmp/workspace",
        branch: "feat-x",
        force: true,
      }),
    ).rejects.toThrow(/force.push.*not allowed/i);
  });

  test("rejects push to protected branches", async () => {
    await expect(
      pushBranch({
        installationId: 12345,
        owner: "alice",
        repo: "my-repo",
        workspacePath: "/tmp/workspace",
        branch: "main",
        force: false,
      }),
    ).rejects.toThrow(/protected/i);
  });

  test("rejects push to custom default branch", async () => {
    await expect(
      pushBranch({
        installationId: 12345,
        owner: "alice",
        repo: "my-repo",
        workspacePath: "/tmp/workspace",
        branch: "develop",
        force: false,
        defaultBranch: "develop",
      }),
    ).rejects.toThrow(/protected/i);
  });

  test("rejects branch with invalid format (double dots)", async () => {
    await expect(
      pushBranch({
        installationId: 12345,
        owner: "alice",
        repo: "my-repo",
        workspacePath: "/tmp/workspace",
        branch: "feat..branch",
        force: false,
      }),
    ).rejects.toThrow(/\.\./);
  });

  test("successful push delegates to gitWithInstallationAuth with correct args", async () => {
    const result = await pushBranch({
      installationId: 12345,
      owner: "alice",
      repo: "my-repo",
      workspacePath: "/tmp/workspace",
      branch: "feat-new-feature",
      force: false,
    });

    expect(result).toEqual({ branch: "feat-new-feature", pushed: true });

    // The authenticated push goes through gitWithInstallationAuth — not
    // via a hand-rolled credential.helper=! pattern.
    expect(mockGitWithAuth).toHaveBeenCalledTimes(1);
    const [args, installationId, opts] = mockGitWithAuth.mock.calls[0];
    expect(args).toEqual([
      "push",
      "https://github.com/alice/my-repo.git",
      "HEAD:refs/heads/feat-new-feature",
    ]);
    expect(installationId).toBe(12345);
    expect(opts).toMatchObject({
      cwd: "/tmp/workspace",
      timeout: 120_000,
    });
  });

  test("sets git author to Soleur Agent identity", async () => {
    await pushBranch({
      installationId: 12345,
      owner: "alice",
      repo: "my-repo",
      workspacePath: "/tmp/workspace",
      branch: "feat-x",
      force: false,
    });

    // `git config user.name/user.email` still run via execFileSync
    // (identity setup is independent of the push's credential plumbing).
    const configCalls = mockExecFileSync.mock.calls.filter(
      (call: unknown[]) =>
        Array.isArray(call[1]) && (call[1] as string[]).includes("config"),
    );
    expect(configCalls.length).toBeGreaterThanOrEqual(2);

    const nameCall = configCalls.find(
      (call: unknown[]) => (call[1] as string[]).includes("user.name"),
    );
    expect(nameCall![1]).toContain("Soleur Agent");

    const emailCall = configCalls.find(
      (call: unknown[]) => (call[1] as string[]).includes("user.email"),
    );
    expect(emailCall![1]).toContain("agent@soleur.ai");
  });

  test("wraps push failure stderr in user-safe error", async () => {
    const err = new Error("push failed") as Error & { stderr?: Buffer };
    err.stderr = Buffer.from("remote: error: permission denied /home/soleur/askpass-abc.sh");
    mockGitWithAuth.mockRejectedValueOnce(err);

    await expect(
      pushBranch({
        installationId: 12345,
        owner: "alice",
        repo: "my-repo",
        workspacePath: "/tmp/workspace",
        branch: "feat-x",
        force: false,
      }),
    ).rejects.toThrow(/Git push failed/);
  });

  test("with a pinned commitSha the refspec is <sha>:refs/heads/<branch> after a cat-file check", async () => {
    const sha = "a".repeat(40);
    await pushBranch({
      installationId: 1,
      owner: "alice",
      repo: "my-repo",
      workspacePath: "/tmp/workspace",
      branch: "feat-x",
      force: false,
      commitSha: sha,
    });
    const verify = mockExecFileSync.mock.calls.find((c: unknown[]) => (c[1] as string[]).includes("cat-file"));
    expect(verify![1]).toEqual(["cat-file", "-e", `${sha}^{commit}`]);
    expect(mockGitWithAuth.mock.calls[0][0]).toEqual(["push", "https://github.com/alice/my-repo.git", `${sha}:refs/heads/feat-x`]);
  });

  test("a pinned commitSha that is not a full sha throws before any git call", async () => {
    for (const bad of ["HEAD", "abc123", "A".repeat(40), `${"a".repeat(40)} `, "-f"]) {
      await expect(
        pushBranch({ installationId: 1, owner: "a", repo: "r", workspacePath: "/tmp/w", branch: "feat-x", force: false, commitSha: bad }),
      ).rejects.toThrow(/valid full commit sha/);
    }
    expect(mockGitWithAuth).not.toHaveBeenCalled();
  });

  test("a pinned commitSha absent from the repository throws and nothing is pushed", async () => {
    mockExecFileSync.mockImplementation((_cmd: string, args: string[]) => {
      if (args.includes("cat-file")) throw new Error("fatal: Not a valid object name");
      return Buffer.from("");
    });
    await expect(
      pushBranch({ installationId: 1, owner: "a", repo: "r", workspacePath: "/tmp/w", branch: "feat-x", force: false, commitSha: "b".repeat(40) }),
    ).rejects.toThrow(/not present/);
    expect(mockGitWithAuth).not.toHaveBeenCalled();
  });
});
