import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync, mkdirSync, existsSync, writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
// #7849: the fixture environment comes from the fixture-env builder, not the bare sweep. The
// sweep alone stops git being POINTED elsewhere; it does not stop git WALKING UP into an
// enclosing repository from the fixture, neutralise the developer own config, or supply an
// identity -- the three things a fixture that WRITES needs.
import { gitFixtureEnv } from "./lib/git-fixture-env";

const HOOK_PATH = join(import.meta.dir, "../hooks/welcome-hook.sh");

// Build a clean env excluding all GIT_* variables that lefthook injects.

function createTempGitRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "welcome-hook-test-"));
  Bun.spawnSync(["git", "init", dir], {
    env: gitFixtureEnv(dir),
    stdout: "ignore",
    stderr: "ignore",
  });
  return dir;
}

function runHook(cwd: string, codex = false): { exitCode: number; stdout: string; stderr: string } {
  const environment = gitFixtureEnv(cwd);
  delete environment.CODEX_THREAD_ID;
  delete environment.PLUGIN_ROOT;
  if (codex) environment.CODEX_THREAD_ID = "test-codex-thread";
  const result = Bun.spawnSync(["bash", HOOK_PATH], {
    cwd,
    env: environment,
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  };
}

describe("welcome-hook first-session sentinel", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempGitRepo();
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  test("Codex uses its own bootstrap without a Claude welcome sentinel", () => {
    const result = runHook(tempDir, true);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
    expect(existsSync(join(tempDir, ".claude", "soleur-welcomed.local"))).toBe(false);
  });

  test("git repo without a plugins/soleur dir (marketplace install): creates sentinel and outputs welcome JSON", () => {
    // The hook's own SessionStart registration implies the plugin is active;
    // a vendored plugins/soleur directory is a dev-checkout artifact that real
    // (marketplace) installs never carry.
    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(existsSync(join(tempDir, ".claude", "soleur-welcomed.local"))).toBe(true);
    expect(result.stdout).toContain("hookSpecificOutput");
    expect(result.stdout).toContain("SessionStart");
  });

  test("second project gets its own sentinel (welcome is per-project)", () => {
    const other = createTempGitRepo();
    try {
      const first = runHook(tempDir);
      const second = runHook(other);
      expect(first.stdout).toContain("hookSpecificOutput");
      expect(second.stdout).toContain("hookSpecificOutput");
      expect(existsSync(join(other, ".claude", "soleur-welcomed.local"))).toBe(true);
    } finally {
      rmSync(other, { recursive: true, force: true });
    }
  });

  test("project with existing sentinel: exits 0 immediately, no output", () => {
    mkdirSync(join(tempDir, ".claude"), { recursive: true });
    writeFileSync(join(tempDir, ".claude", "soleur-welcomed.local"), "");

    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("git repo with CLAUDE.md not referencing soleur: still welcomed (plugin registration is the predicate)", () => {
    writeFileSync(join(tempDir, "CLAUDE.md"), "# My Project\n\nSome instructions.");

    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(existsSync(join(tempDir, ".claude", "soleur-welcomed.local"))).toBe(true);
  });
});
