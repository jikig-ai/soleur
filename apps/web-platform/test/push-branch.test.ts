/**
 * Push Branch Tool Tests (Phase 4, #1929)
 *
 * Tests the github_push_branch handler function:
 * - Branch name validation (rejects main/master/default)
 * - Force-push blocking
 * - Branch format validation (git ref format rules)
 * - Credential helper lifecycle (create → push → cleanup)
 * - Git author configuration
 */
import { describe, test, expect, vi, beforeEach } from "vitest";

// Mock child_process and fs before importing push-branch
const { mockExecFileSync, mockWriteFileSync, mockUnlinkSync } = vi.hoisted(() => ({
  mockExecFileSync: vi.fn(),
  mockWriteFileSync: vi.fn(),
  mockUnlinkSync: vi.fn(),
}));

vi.mock("child_process", () => ({
  execFileSync: mockExecFileSync,
}));

vi.mock("fs", () => ({
  writeFileSync: mockWriteFileSync,
  unlinkSync: mockUnlinkSync,
}));

vi.mock("../server/github-app", () => ({
  generateInstallationToken: vi.fn(async () => "ghs_test_token_123"),
  randomCredentialPath: vi.fn(() => "/tmp/git-cred-test-uuid"),
}));

vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

import {
  validateBranchName,
  PROTECTED_BRANCHES,
  pushBranch,
} from "../server/push-branch";

describe("validateBranchName", () => {
  test("rejects 'main'", () => {
    expect(() => validateBranchName("main")).toThrow(/protected/i);
  });

  test("rejects 'master'", () => {
    expect(() => validateBranchName("master")).toThrow(/protected/i);
  });

  test("rejects custom default branch", () => {
    expect(() => validateBranchName("develop", "develop")).toThrow(/protected/i);
  });

  test("allows feature branches", () => {
    expect(() => validateBranchName("feat-ci-cd")).not.toThrow();
  });

  test("allows branches with slashes", () => {
    expect(() => validateBranchName("fix/bug-123")).not.toThrow();
  });

  test("PROTECTED_BRANCHES includes main and master", () => {
    expect(PROTECTED_BRANCHES).toContain("main");
    expect(PROTECTED_BRANCHES).toContain("master");
  });
});

describe("pushBranch", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Default: all execFileSync calls succeed
    mockExecFileSync.mockReturnValue(Buffer.from(""));
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

  test("successful push calls git with correct args", async () => {
    const result = await pushBranch({
      installationId: 12345,
      owner: "alice",
      repo: "my-repo",
      workspacePath: "/tmp/workspace",
      branch: "feat-new-feature",
      force: false,
    });

    expect(result).toEqual({ branch: "feat-new-feature", pushed: true });

    // Verify the push command (URL assertion pattern from CI/CD learning)
    const pushCall = mockExecFileSync.mock.calls.find(
      (call: unknown[]) => Array.isArray(call[1]) && (call[1] as string[]).includes("push"),
    );
    expect(pushCall).toBeDefined();
    expect(pushCall![0]).toBe("git");
    expect(pushCall![1]).toEqual(
      expect.arrayContaining([
        "push",
        "https://github.com/alice/my-repo.git",
        "HEAD:refs/heads/feat-new-feature",
      ]),
    );
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

    // First two execFileSync calls are git config for author
    const configCalls = mockExecFileSync.mock.calls.filter(
      (call: unknown[]) => Array.isArray(call[1]) && (call[1] as string[]).includes("config"),
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

  test("credential helper is created and cleaned up on success", async () => {
    await pushBranch({
      installationId: 12345,
      owner: "alice",
      repo: "my-repo",
      workspacePath: "/tmp/workspace",
      branch: "feat-x",
      force: false,
    });

    // writeFileSync creates the credential helper
    expect(mockWriteFileSync).toHaveBeenCalledTimes(1);
    expect(mockWriteFileSync.mock.calls[0][0]).toBe("/tmp/git-cred-test-uuid");
    expect(mockWriteFileSync.mock.calls[0][2]).toEqual({ mode: 0o700 });

    // unlinkSync cleans it up
    expect(mockUnlinkSync).toHaveBeenCalledTimes(1);
    expect(mockUnlinkSync.mock.calls[0][0]).toBe("/tmp/git-cred-test-uuid");
  });

  test("credential helper is cleaned up even on push failure", async () => {
    mockExecFileSync.mockImplementation((_cmd: string, args: string[]) => {
      if (Array.isArray(args) && args.includes("push")) {
        const err = new Error("push failed") as Error & { stderr: Buffer };
        err.stderr = Buffer.from("remote: error");
        throw err;
      }
      return Buffer.from("");
    });

    await expect(
      pushBranch({
        installationId: 12345,
        owner: "alice",
        repo: "my-repo",
        workspacePath: "/tmp/workspace",
        branch: "feat-x",
        force: false,
      }),
    ).rejects.toThrow(/push failed|Git push failed/);

    // Finally block still runs
    expect(mockUnlinkSync).toHaveBeenCalledTimes(1);
  });
});
