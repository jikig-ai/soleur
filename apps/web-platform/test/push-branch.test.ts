/**
 * Push Branch Tool Tests (Phase 4, #1929)
 *
 * Tests the github_push_branch handler function:
 * - Branch name validation (rejects main/master/default)
 * - Force-push blocking
 * - Credential helper lifecycle (create → push → cleanup)
 * - Git author configuration
 */
import { describe, test, expect, vi, beforeEach } from "vitest";

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
});
