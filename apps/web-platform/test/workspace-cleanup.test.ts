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

  test("throws with cleanup instructions when all phases fail", async () => {
    // Mock child_process to simulate root-owned files that can't be deleted.
    // Real root-owned files can't be created in tests without elevated privileges.
    vi.resetModules();

    vi.doMock("child_process", () => ({
      execFileSync: (cmd: string) => {
        if (cmd === "rm" || cmd === "find" || cmd === "rmdir") {
          const err = new Error("Permission denied") as Error & {
            stderr: Buffer;
          };
          err.stderr = Buffer.from("Permission denied");
          throw err;
        }
        return Buffer.alloc(0);
      },
    }));

    vi.doMock("fs", async () => {
      const actual = await vi.importActual<typeof import("fs")>("fs");
      return { ...actual, existsSync: () => true };
    });

    const { removeWorkspaceDir: mockedRemove } = await import(
      "../server/workspace"
    );

    expect(() => mockedRemove("/workspaces/test-cleanup")).toThrow(
      /Workspace cleanup failed.*Manual cleanup required/,
    );
  });
});
