// Set env BEFORE any imports (module reads at load time)
import { tmpdir } from "os";
process.env.WORKSPACES_ROOT = "/tmp/soleur-test-workspaces-err";
process.env.SOLEUR_PLUGIN_PATH = "/nonexistent";
process.env.GIT_CEILING_DIRECTORIES = tmpdir();
delete process.env.GIT_DIR;
delete process.env.GIT_INDEX_FILE;
delete process.env.GIT_WORK_TREE;

import { describe, test, expect, afterEach, beforeEach, vi } from "vitest";
import { existsSync, rmSync } from "fs";
import { randomUUID } from "crypto";

const TEST_WORKSPACES = "/tmp/soleur-test-workspaces-err";

beforeEach(() => {
  vi.resetModules();
});

afterEach(() => {
  vi.restoreAllMocks();
  try {
    rmSync(TEST_WORKSPACES, { recursive: true, force: true });
  } catch {}
});

describe("provisionWorkspaceWithRepo error wrapping", () => {
  test("wraps token generation failure with step-specific message", async () => {
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi
        .fn()
        .mockRejectedValue(new Error("GitHub installation token request failed: 401")),
      randomCredentialPath: vi.fn().mockReturnValue(`/tmp/git-cred-${randomUUID()}`),
    }));

    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();

    await expect(
      provisionWorkspaceWithRepo(userId, "https://github.com/test/repo", 12345),
    ).rejects.toThrow(/Token generation failed/);
  });

  test("wraps git clone failure with stderr output", async () => {
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken123"),
      randomCredentialPath: vi.fn().mockReturnValue(`/tmp/git-cred-${randomUUID()}`),
    }));

    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();

    // Clone will fail because the repo URL is fake — git stderr should be in the message
    await expect(
      provisionWorkspaceWithRepo(userId, "https://github.com/nonexistent/fake-repo-xxx", 12345),
    ).rejects.toThrow(/Git clone failed/);
  });

  test("cleans up credential helper even when clone fails", async () => {
    const credPath = `/tmp/git-cred-${randomUUID()}`;
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken123"),
      randomCredentialPath: vi.fn().mockReturnValue(credPath),
    }));

    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();

    await expect(
      provisionWorkspaceWithRepo(userId, "https://github.com/nonexistent/fake-repo-xxx", 12345),
    ).rejects.toThrow();

    // Credential helper should be cleaned up
    expect(existsSync(credPath)).toBe(false);
  });
});
