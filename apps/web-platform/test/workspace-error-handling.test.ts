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

    // Stub execFile (used by git-auth.ts via promisify) to invoke the
    // callback with a realistic stderr buffer. Test becomes deterministic
    // + network-independent: git stderr flows through the production
    // error-wrapping path in workspace.ts.
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFile: vi
          .fn()
          .mockImplementation(
            (
              cmd: string,
              args: string[],
              _opts: Record<string, unknown>,
              cb: (
                err: Error | null,
                result: { stdout: Buffer; stderr: Buffer },
              ) => void,
            ) => {
              if (cmd === "git" && args.includes("clone")) {
                const err: Error & { stderr?: Buffer } = new Error("git exited 128");
                err.stderr = Buffer.from(
                  "fatal: repository 'https://github.com/nonexistent/fake-repo-xxx/' not found\n",
                );
                cb(err, { stdout: Buffer.from(""), stderr: err.stderr });
                return;
              }
              cb(null, { stdout: Buffer.from(""), stderr: Buffer.from("") });
            },
          ),
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

  test("cleans up askpass script even when clone fails", async () => {
    vi.doMock("../server/github-app", () => ({
      generateInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken123"),
      // randomCredentialPath stub kept for symmetry with sibling tests; the
      // deprecated export is being swept by #2848. Removing it here would be
      // out of scope for the flake fix.
      randomCredentialPath: vi.fn().mockReturnValue(`/tmp/git-cred-${randomUUID()}`),
      checkRepoAccess: vi.fn().mockResolvedValue("ok"),
    }));

    let capturedAskpassPath: string | undefined;

    // NOTE: factory does NOT throw — error is injected through the execFile
    // callback. Avoids the vitest-wrapper-message swallowing class documented
    // in 2026-05-07-vitest-domock-factory-throw-wrapped-message.md.
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFile: vi
          .fn()
          .mockImplementation(
            (
              cmd: string,
              args: string[],
              opts: { env?: NodeJS.ProcessEnv; cwd?: string; timeout?: number } | undefined,
              cb: (err: Error | null, result: { stdout: Buffer; stderr: Buffer }) => void,
            ) => {
              if (cmd === "git" && args.includes("clone")) {
                // Canonical pattern: capture GIT_ASKPASS off the env block
                // that gitWithInstallationAuth (git-auth.ts) sets right
                // before invoking execFile. This is the ACTUAL artifact the
                // try/finally in git-auth.ts cleans up. Mirror of
                // git-auth.test.ts:223-244.
                capturedAskpassPath = opts?.env?.GIT_ASKPASS;
                const err: Error & { stderr?: Buffer } = new Error("git exited 128");
                err.stderr = Buffer.from(
                  "fatal: repository 'https://github.com/nonexistent/fake-repo-xxx/' not found\n",
                );
                cb(err, { stdout: Buffer.from(""), stderr: err.stderr });
                return;
              }
              cb(null, { stdout: Buffer.from(""), stderr: Buffer.from("") });
            },
          ),
      };
    });

    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();

    await expect(
      provisionWorkspaceWithRepo(userId, "https://github.com/nonexistent/fake-repo-xxx", 12345),
    ).rejects.toThrow();

    // Cleanup contract: gitWithInstallationAuth's finally block unlinks the
    // askpass script even on clone failure.
    expect(capturedAskpassPath).toBeTruthy();
    expect(existsSync(capturedAskpassPath!)).toBe(false);
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
        // post-GIT_ASKPASS migration, git-auth.ts uses execFile + promisify
        // for async non-blocking exec — simulate a successful clone by
        // creating the target dir before invoking the callback.
        execFile: vi
          .fn()
          .mockImplementation(
            (
              cmd: string,
              args: string[],
              _opts: Record<string, unknown>,
              cb: (
                err: Error | null,
                result: { stdout: Buffer; stderr: Buffer },
              ) => void,
            ) => {
              if (cmd === "git" && args.includes("clone")) {
                const targetDir = args[args.length - 1];
                const { mkdirSync, writeFileSync } = require("fs");
                mkdirSync(targetDir, { recursive: true });
                mkdirSync(join(targetDir, ".git"), { recursive: true });
                writeFileSync(
                  join(targetDir, ".git", "HEAD"),
                  "ref: refs/heads/main\n",
                );
              }
              cb(null, {
                stdout: Buffer.from(""),
                stderr: Buffer.from(""),
              });
            },
          ),
        // Workspace's git config user.name/email still run sync — preserve.
        execFileSync: vi
          .fn()
          .mockImplementation(
            (cmd: string, args: string[], opts?: Record<string, unknown>) =>
              origExecFileSync(cmd, args, opts),
          ),
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
        execFile: vi
          .fn()
          .mockImplementation(
            (
              cmd: string,
              args: string[],
              _opts: Record<string, unknown>,
              cb: (
                err: Error | null,
                result: { stdout: Buffer; stderr: Buffer },
              ) => void,
            ) => {
              if (cmd === "git" && args.includes("clone")) {
                const targetDir = args[args.length - 1];
                const { mkdirSync, writeFileSync } = require("fs");
                mkdirSync(targetDir, { recursive: true });
                mkdirSync(join(targetDir, ".git"), { recursive: true });
                writeFileSync(
                  join(targetDir, ".git", "HEAD"),
                  "ref: refs/heads/main\n",
                );
              }
              cb(null, {
                stdout: Buffer.from(""),
                stderr: Buffer.from(""),
              });
            },
          ),
        execFileSync: vi
          .fn()
          .mockImplementation(
            (cmd: string, args: string[], opts?: Record<string, unknown>) =>
              origExecFileSync(cmd, args, opts),
          ),
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
