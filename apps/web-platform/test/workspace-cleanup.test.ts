// Set env BEFORE any imports (module reads at load time)
import { tmpdir } from "os";
process.env.WORKSPACES_ROOT = "/tmp/soleur-test-workspaces-cleanup";
process.env.SOLEUR_PLUGIN_PATH = "/nonexistent";
process.env.GIT_CEILING_DIRECTORIES = tmpdir();
delete process.env.GIT_DIR;
delete process.env.GIT_INDEX_FILE;
delete process.env.GIT_WORK_TREE;

import { describe, test, expect, afterEach, beforeEach, vi } from "vitest";
import {
  existsSync,
  mkdirSync,
  writeFileSync,
  chmodSync,
  rmSync,
} from "fs";
import { join } from "path";
import { execFileSync } from "child_process";
import { removeWorkspaceDir } from "../server/workspace";

const TEST_ROOT = "/tmp/soleur-test-workspaces-cleanup";

function forceCleanup(): void {
  try {
    // Recursively restore permissions so rmSync can delete everything
    execFileSync("chmod", ["-R", "u+rwX", TEST_ROOT], { stdio: "pipe" });
  } catch {}
  try {
    rmSync(TEST_ROOT, { recursive: true, force: true });
  } catch {}
}

beforeEach(() => {
  forceCleanup();
});

afterEach(() => {
  forceCleanup();
});

function createTestWorkspace(name: string): string {
  const dir = join(TEST_ROOT, name);
  mkdirSync(dir, { recursive: true });
  return dir;
}

describe("removeWorkspaceDir", () => {
  test("removes a normal directory (Phase 1 rm -rf succeeds)", () => {
    const ws = createTestWorkspace("normal");
    writeFileSync(join(ws, "file.txt"), "hello");
    mkdirSync(join(ws, "subdir"));
    writeFileSync(join(ws, "subdir", "nested.txt"), "world");

    removeWorkspaceDir(ws);

    expect(existsSync(ws)).toBe(false);
  });

  test("returns immediately when directory does not exist", () => {
    const ws = join(TEST_ROOT, "nonexistent-" + Date.now());

    // Should not throw
    removeWorkspaceDir(ws);

    expect(existsSync(ws)).toBe(false);
  });

  test("removes directory with restrictive permission bits via Phase 2 fallback", () => {
    const ws = createTestWorkspace("restrictive");
    const subdir = join(ws, "locked-dir");
    mkdirSync(subdir);
    writeFileSync(join(subdir, "readonly.txt"), "data");

    // Simulate git pack file permissions: file mode 444, dir mode 555
    chmodSync(join(subdir, "readonly.txt"), 0o000);
    chmodSync(subdir, 0o555);

    removeWorkspaceDir(ws);

    expect(existsSync(ws)).toBe(false);
  });

  test("moves workspace aside when rm/find/rmdir fail but mv succeeds", async () => {
    vi.resetModules();

    const calls: string[] = [];
    let mvArgs: string[] = [];
    vi.doMock("child_process", async () => {
      const actual =
        await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, args: string[]) => {
          calls.push(cmd);
          if (cmd === "mv") {
            mvArgs = args;
          }
          if (cmd === "rm" || cmd === "find" || cmd === "rmdir") {
            const err = new Error("Permission denied") as Error & {
              stderr: Buffer;
            };
            err.stderr = Buffer.from("Permission denied");
            throw err;
          }
          // chmod and mv succeed
          return Buffer.alloc(0);
        },
      };
    });

    vi.doMock("fs", async () => {
      const actual = await vi.importActual<typeof import("fs")>("fs");
      return { ...actual, existsSync: () => true };
    });

    const { removeWorkspaceDir: mockedRemove } = await import(
      "../server/workspace"
    );

    // Should NOT throw -- mv-aside succeeds
    expect(() => mockedRemove(TEST_ROOT + "/test-cleanup")).not.toThrow();
    // Verify all phases attempted in order before falling back to mv
    expect(calls).toEqual(["rm", "chmod", "find", "rmdir", "mv"]);
    // Verify mv destination uses the .orphaned- suffix pattern
    expect(mvArgs).toHaveLength(2);
    expect(mvArgs[0]).toBe(TEST_ROOT + "/test-cleanup");
    expect(mvArgs[1]).toMatch(/\.orphaned-\d+$/);
  });

  test("throws user-friendly error (no sudo) when all phases including mv fail", async () => {
    vi.resetModules();

    vi.doMock("child_process", async () => {
      const actual =
        await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string) => {
          if (cmd === "rm" || cmd === "find" || cmd === "rmdir" || cmd === "mv") {
            const err = new Error("Permission denied") as Error & {
              stderr: Buffer;
            };
            err.stderr = Buffer.from("Permission denied");
            throw err;
          }
          return Buffer.alloc(0);
        },
      };
    });

    vi.doMock("fs", async () => {
      const actual = await vi.importActual<typeof import("fs")>("fs");
      return { ...actual, existsSync: () => true };
    });

    const { removeWorkspaceDir: mockedRemove } = await import(
      "../server/workspace"
    );

    let thrown: Error | undefined;
    try {
      mockedRemove(TEST_ROOT + "/test-cleanup");
    } catch (e) {
      thrown = e as Error;
    }
    expect(thrown).toBeDefined();
    expect(thrown!.message).toMatch(/please try again or contact support/);
    // Must NOT contain sudo instructions
    expect(thrown!.message).not.toMatch(/sudo/);
  });
});

describe("removeWorkspaceDir path validation", () => {
  test("rejects path outside workspace root", () => {
    expect(() => removeWorkspaceDir("/etc/passwd")).toThrow(
      "Refusing to remove path outside workspace root",
    );
  });

  test("rejects the workspace root itself", () => {
    expect(() => removeWorkspaceDir(TEST_ROOT)).toThrow(
      "Refusing to remove path outside workspace root",
    );
  });

  test("rejects prefix collision (e.g. /root-evil when root is /root)", () => {
    expect(() => removeWorkspaceDir(TEST_ROOT + "-evil")).toThrow(
      "Refusing to remove path outside workspace root",
    );
  });

  test("rejects traversal that resolves outside root", () => {
    expect(() =>
      removeWorkspaceDir(TEST_ROOT + "/user/../../../etc"),
    ).toThrow("Refusing to remove path outside workspace root");
  });

  test("rejects empty string (resolves to CWD)", () => {
    expect(() => removeWorkspaceDir("")).toThrow(
      "Refusing to remove path outside workspace root",
    );
  });

  test("accepts valid workspace subdirectory path", () => {
    const ws = join(TEST_ROOT, "valid-workspace");
    mkdirSync(ws, { recursive: true });
    // Should not throw - proceeds to normal removal logic
    removeWorkspaceDir(ws);
    expect(existsSync(ws)).toBe(false);
  });
});
