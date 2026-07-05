// Unit tests for seedWorktreeConfig — the host-side HEAL that removes the harmful
// extensions.worktreeConfig a prior version wrote, so in-sandbox git (reading a masked
// .git/config.worktree) stops fataling and `git worktree add` runs natively (#4826).
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

describe("seedWorktreeConfig (heal)", () => {
  test("removes the harmful extensions.worktreeConfig a prior seed wrote", () => {
    const dir = freshRepo();
    // Simulate a workspace broken by the old seed.
    execFileSync("git", ["config", "extensions.worktreeConfig", "true"], { cwd: dir, stdio: "pipe" });
    execFileSync("git", ["config", "core.repositoryformatversion", "1"], { cwd: dir, stdio: "pipe" });
    seedWorktreeConfig(dir);
    expect(cfg(dir, "extensions.worktreeConfig")).toBeNull(); // unset → in-sandbox git works
    expect(cfg(dir, "core.repositoryformatversion")).toBe("0"); // reset to plain-repo default
  });

  test("no-ops on a healthy normal repo (no worktreeConfig to remove)", () => {
    const dir = freshRepo();
    seedWorktreeConfig(dir);
    expect(cfg(dir, "extensions.worktreeConfig")).toBeNull();
    // A healthy clone is untouched — repositoryformatversion stays whatever git init set.
  });

  test("is idempotent — a second run does not throw and keeps it healed", () => {
    const dir = freshRepo();
    execFileSync("git", ["config", "extensions.worktreeConfig", "true"], { cwd: dir, stdio: "pipe" });
    seedWorktreeConfig(dir);
    expect(() => seedWorktreeConfig(dir)).not.toThrow();
    expect(cfg(dir, "extensions.worktreeConfig")).toBeNull();
  });

  test("no-ops (no throw) when the path has no .git directory", () => {
    const empty = mkdtempSync(join(tmpdir(), "seed-empty-"));
    made.push(empty);
    expect(() => seedWorktreeConfig(empty)).not.toThrow();
    expect(cfg(empty, "extensions.worktreeConfig")).toBeNull();
  });
});
