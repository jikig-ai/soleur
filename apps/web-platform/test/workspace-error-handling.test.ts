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
import { join } from "path";
import { randomUUID } from "crypto";

const TEST_WORKSPACES = "/tmp/soleur-test-workspaces-err";

beforeEach(() => {
  vi.resetModules();
});

afterEach(() => {
  vi.restoreAllMocks();
  // Clear module-level mocks so mocks set via vi.doMock in one test don't leak
  // into the next (vi.resetModules alone doesn't clear vi.doMock registrations).
  vi.doUnmock("child_process");
  vi.doUnmock("../server/github-app");
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
      checkRepoAccess: vi.fn().mockResolvedValue("ok"),
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
      checkRepoAccess: vi.fn().mockResolvedValue("ok"),
    }));

    // Stub execFileSync so git clone throws synchronously with a realistic stderr
    // buffer. This makes the test deterministic and network-independent — the
    // production error-wrapping code at workspace.ts:172 reads .stderr?.toString()
    // and produces the "Git clone failed: ..." message we assert below.
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: vi.fn().mockImplementation((cmd: string, args: string[]) => {
          if (cmd === "git" && Array.isArray(args) && args.includes("clone")) {
            const err: Error & { stderr?: Buffer } = new Error("git exited 128");
            err.stderr = Buffer.from(
              "fatal: repository 'https://github.com/nonexistent/fake-repo-xxx/' not found\n",
            );
            throw err;
          }
          // Other git invocations (config user.name/user.email) shouldn't be reached
          // because the clone failure rejects first; return empty buffer defensively.
          return Buffer.from("");
        }),
      };
    });

    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();

    // Clone will fail because execFileSync is stubbed to throw — git stderr
    // flows through the production error-wrapping path.
    await expect(
      provisionWorkspaceWithRepo(userId, "https://github.com/nonexistent/fake-repo-xxx", 12345),
    ).rejects.toThrow(/Git clone failed/);
  });

  test("cleans up credential helper even when clone fails", async () => {
    const credPath = `/tmp/git-cred-${randomUUID()}`;
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken123"),
      randomCredentialPath: vi.fn().mockReturnValue(credPath),
      checkRepoAccess: vi.fn().mockResolvedValue("ok"),
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

describe("provisionWorkspace sentinel file", () => {
  test("creates soleur-welcomed.local sentinel in .claude/", async () => {
    const { provisionWorkspace } = await import("../server/workspace");
    const userId = randomUUID();
    const workspacePath = await provisionWorkspace(userId);

    expect(existsSync(join(workspacePath, ".claude", "soleur-welcomed.local"))).toBe(true);
  });
});

describe("provisionWorkspaceWithRepo sentinel file", () => {
  test("does NOT create sentinel when suppressWelcomeHook is omitted", async () => {
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken123"),
      randomCredentialPath: vi.fn().mockReturnValue(`/tmp/git-cred-${randomUUID()}`),
      checkRepoAccess: vi.fn().mockResolvedValue("ok"),
    }));

    // Mock execFileSync to simulate successful clone (create workspace dir with .git)
    const origExecFileSync = (await import("child_process")).execFileSync;
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: vi.fn().mockImplementation((cmd: string, args: string[], opts?: Record<string, unknown>) => {
          if (cmd === "git" && args[0] === "-c") {
            // Simulate clone: create the directory with a .git marker
            const targetDir = args[args.length - 1];
            const { mkdirSync, writeFileSync } = require("fs");
            mkdirSync(targetDir, { recursive: true });
            mkdirSync(join(targetDir, ".git"), { recursive: true });
            writeFileSync(join(targetDir, ".git", "HEAD"), "ref: refs/heads/main\n");
            return Buffer.from("");
          }
          return origExecFileSync(cmd, args, opts);
        }),
      };
    });

    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();
    const workspacePath = await provisionWorkspaceWithRepo(
      userId, "https://github.com/test/repo", 12345,
    );

    expect(existsSync(join(workspacePath, ".claude", "soleur-welcomed.local"))).toBe(false);
  });

  test("creates sentinel when suppressWelcomeHook is true", async () => {
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken123"),
      randomCredentialPath: vi.fn().mockReturnValue(`/tmp/git-cred-${randomUUID()}`),
      checkRepoAccess: vi.fn().mockResolvedValue("ok"),
    }));

    const origExecFileSync = (await import("child_process")).execFileSync;
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: vi.fn().mockImplementation((cmd: string, args: string[], opts?: Record<string, unknown>) => {
          if (cmd === "git" && args[0] === "-c") {
            const targetDir = args[args.length - 1];
            const { mkdirSync, writeFileSync } = require("fs");
            mkdirSync(targetDir, { recursive: true });
            mkdirSync(join(targetDir, ".git"), { recursive: true });
            writeFileSync(join(targetDir, ".git", "HEAD"), "ref: refs/heads/main\n");
            return Buffer.from("");
          }
          return origExecFileSync(cmd, args, opts);
        }),
      };
    });

    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();
    const workspacePath = await provisionWorkspaceWithRepo(
      userId, "https://github.com/test/repo", 12345,
      undefined, undefined, { suppressWelcomeHook: true },
    );

    expect(existsSync(join(workspacePath, ".claude", "soleur-welcomed.local"))).toBe(true);
  });
});
