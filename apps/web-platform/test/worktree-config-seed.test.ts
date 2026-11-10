// Unit tests for seedWorktreeConfig — the host-side HEAL that removes the harmful
// extensions.worktreeConfig a prior version wrote, so in-sandbox git (reading a masked
// .git/config.worktree) stops fataling and `git worktree add` runs natively (#4826).
import { describe, test, expect, afterEach } from "vitest";
import { execFileSync } from "child_process";
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { seedWorktreeConfig } from "../server/worktree-config-seed";
// #7849: obtain the fixture environment from the shared helper rather than spelling it here. The
// runtime tripwire stops git being POINTED elsewhere; it does not stop git WALKING UP into an
// enclosing repository from the fixture, neutralise the developer own config, or supply an
// identity. Those three are what this builder adds.
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const made: string[] = [];
function freshRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "seed-test-"));
  made.push(dir);
  execFileSync("git", ["init", "-q"], { cwd: dir, stdio: "pipe", env: gitFixtureEnv(dir) });
  return dir;
}
function cfg(dir: string, key: string): string | null {
  try {
    return execFileSync("git", ["config", "--get", key], {
      cwd: dir,
      stdio: "pipe",
      env: gitFixtureEnv(dir),
    })
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
    execFileSync("git", ["config", "extensions.worktreeConfig", "true"], {
      cwd: dir,
      stdio: "pipe",
      env: gitFixtureEnv(dir),
    });
    execFileSync("git", ["config", "core.repositoryformatversion", "1"], {
      cwd: dir,
      stdio: "pipe",
      env: gitFixtureEnv(dir),
    });
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
    execFileSync("git", ["config", "extensions.worktreeConfig", "true"], {
      cwd: dir,
      stdio: "pipe",
      env: gitFixtureEnv(dir),
    });
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

  // Review round: the heal ran `git config` with the full server environment and FOLLOWED a symlinked .git or a commondir into
  // another repository, then WROTE there (measured). It now goes through the host-git invocation, which refuses those shapes.
  test.each(["symlinked .git", "commondir"])("a %s naming another repository: the heal does not touch the other repository", (shape) => {
    const victim = freshRepo();
    execFileSync("git", ["config", "extensions.worktreeConfig", "true"], { cwd: victim, stdio: "pipe", env: gitFixtureEnv(victim) });
    execFileSync("git", ["config", "core.repositoryformatversion", "1"], { cwd: victim, stdio: "pipe", env: gitFixtureEnv(victim) });
    const attacker = freshRepo();
    if (shape === "symlinked .git") {
      rmSync(join(attacker, ".git"), { recursive: true, force: true });
      symlinkSync(join(victim, ".git"), join(attacker, ".git"));
    } else {
      writeFileSync(join(attacker, ".git", "commondir"), `${join(victim, ".git")}\n`);
    }
    expect(() => seedWorktreeConfig(attacker)).not.toThrow();
    // the victim keeps its own (harmful, but its own) values: the write did not land there
    expect(cfg(victim, "extensions.worktreeConfig")).toBe("true");
    expect(cfg(victim, "core.repositoryformatversion")).toBe("1");
  });
});
