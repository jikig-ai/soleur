// Unit tests for seedWorktreeConfig — the host-side pre-seed that makes in-sandbox
// worktree creation a zero-write no-op past the SDK's `.git/config.lock` mask (#4826).
import { describe, test, expect, afterEach } from "vitest";
import { execFileSync } from "child_process";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { seedWorktreeConfig } from "../server/worktree-config-seed";

const made: string[] = [];
function freshRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "seed-test-"));
  made.push(dir);
  execFileSync("git", ["init", "-q"], { cwd: dir, stdio: "pipe" });
  return dir;
}
function cfg(dir: string, key: string): string | null {
  try {
    return execFileSync("git", ["config", "--get", key], { cwd: dir, stdio: "pipe" })
      .toString()
      .trim();
  } catch {
    return null; // git config --get exits non-zero when the key is absent
  }
}

afterEach(() => {
  for (const d of made.splice(0)) {
    try {
      rmSync(d, { recursive: true, force: true });
    } catch {
      /* best-effort */
    }
  }
});

describe("seedWorktreeConfig", () => {
  test("sets the two worktree-config prerequisites", () => {
    const dir = freshRepo();
    seedWorktreeConfig(dir);
    expect(cfg(dir, "extensions.worktreeConfig")).toBe("true");
    expect(cfg(dir, "core.repositoryformatversion")).toBe("1");
  });

  test("clears core.bare / core.worktree so they never live in shared config", () => {
    const dir = freshRepo();
    // A bare-ish leftover the in-sandbox ensure_bare_config would otherwise try to unset.
    execFileSync("git", ["config", "core.bare", "false"], { cwd: dir, stdio: "pipe" });
    seedWorktreeConfig(dir);
    expect(cfg(dir, "core.bare")).toBeNull();
    expect(cfg(dir, "core.worktree")).toBeNull();
  });

  test("is idempotent — a second run keeps the target state and does not throw", () => {
    const dir = freshRepo();
    seedWorktreeConfig(dir);
    expect(() => seedWorktreeConfig(dir)).not.toThrow();
    expect(cfg(dir, "extensions.worktreeConfig")).toBe("true");
  });

  test("no-ops (no throw) when the path has no .git — nothing to seed", () => {
    const empty = mkdtempSync(join(tmpdir(), "seed-empty-"));
    made.push(empty);
    expect(() => seedWorktreeConfig(empty)).not.toThrow();
    // No .git → git config would have errored; the guard skips it entirely.
    expect(cfg(empty, "extensions.worktreeConfig")).toBeNull();
  });
});
