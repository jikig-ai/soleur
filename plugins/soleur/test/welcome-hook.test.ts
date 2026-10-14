import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync, existsSync, writeFileSync, readdirSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
// #7849: the fixture environment comes from the fixture-env builder, not the bare sweep. The
// sweep alone stops git being POINTED elsewhere; it does not stop git WALKING UP into an
// enclosing repository from the fixture, neutralise the developer own config, or supply an
// identity -- the three things a fixture that WRITES needs.
import { gitFixtureEnv } from "./lib/git-fixture-env";

const HOOK_PATH = join(import.meta.dir, "../hooks/welcome-hook.sh");

function createTempGitRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "welcome-hook-test-"));
  Bun.spawnSync(["git", "init", dir], {
    env: gitFixtureEnv(dir),
    stdout: "ignore",
    stderr: "ignore",
  });
  return dir;
}

// The sentinel now lives in $XDG_STATE_HOME (or $HOME/.local/state), NOT inside the
// project — the #1383 regression was exactly "plugin writes .claude/ artifacts into
// every repo the user opens". Each test gets an isolated state dir.
let stateDir: string;

function runHook(cwd: string, codex = false): { exitCode: number; stdout: string; stderr: string } {
  const environment = gitFixtureEnv(cwd);
  delete environment.CODEX_THREAD_ID;
  delete environment.PLUGIN_ROOT;
  environment.XDG_STATE_HOME = stateDir;
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

function welcomedDir(): string {
  return join(stateDir, "soleur", "welcomed");
}

function sentinelCount(): number {
  try {
    return readdirSync(welcomedDir()).length;
  } catch {
    return 0;
  }
}

describe("welcome-hook first-session sentinel", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempGitRepo();
    stateDir = mkdtempSync(join(tmpdir(), "welcome-hook-state-"));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
    rmSync(stateDir, { recursive: true, force: true });
  });

  test("Codex uses its own bootstrap without a welcome sentinel", () => {
    const result = runHook(tempDir, true);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
    expect(sentinelCount()).toBe(0);
  });

  test("PLUGIN_ROOT harness (Codex-compat path): silent, no sentinel", () => {
    const environment = gitFixtureEnv(tempDir);
    delete environment.CODEX_THREAD_ID;
    environment.PLUGIN_ROOT = "/fake/plugin/root";
    environment.XDG_STATE_HOME = stateDir;
    const result = Bun.spawnSync(["bash", HOOK_PATH], {
      cwd: tempDir,
      env: environment,
      stdout: "pipe",
      stderr: "pipe",
    });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString()).toBe("");
    expect(sentinelCount()).toBe(0);
    expect(existsSync(join(tempDir, ".claude"))).toBe(false);
  });

  test("git repo without a plugins/soleur dir (marketplace install): outputs welcome JSON and writes NO project artifact", () => {
    // The hook's own SessionStart registration implies the plugin is installed;
    // a vendored plugins/soleur directory is a dev-checkout artifact that real
    // (marketplace) installs never carry. #1383: the welcome must not leave
    // artifacts inside the user's repo — dedupe lives in the state dir.
    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("hookSpecificOutput");
    expect(result.stdout).toContain("SessionStart");
    expect(existsSync(join(tempDir, ".claude"))).toBe(false);
    expect(sentinelCount()).toBe(1);
  });

  test("second project gets its own sentinel (welcome is per-project)", () => {
    const other = createTempGitRepo();
    try {
      const first = runHook(tempDir);
      const second = runHook(other);
      expect(first.stdout).toContain("hookSpecificOutput");
      expect(second.stdout).toContain("hookSpecificOutput");
      expect(sentinelCount()).toBe(2);
      expect(existsSync(join(other, ".claude"))).toBe(false);
    } finally {
      rmSync(other, { recursive: true, force: true });
    }
  });

  test("repo with existing sentinel: exits 0 immediately, no output, still no project artifact", () => {
    const first = runHook(tempDir);
    expect(first.stdout).toContain("hookSpecificOutput");
    expect(sentinelCount()).toBe(1);

    const second = runHook(tempDir);
    expect(second.exitCode).toBe(0);
    expect(second.stdout).toBe("");
    expect(sentinelCount()).toBe(1);
    expect(existsSync(join(tempDir, ".claude"))).toBe(false);
  });

  test("git repo with CLAUDE.md not referencing soleur: still welcomed, still no project write", () => {
    writeFileSync(join(tempDir, "CLAUDE.md"), "# My Project\n\nSome instructions.");

    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("hookSpecificOutput");
    expect(sentinelCount()).toBe(1);
    expect(existsSync(join(tempDir, ".claude"))).toBe(false);
  });

  test("state dir unwritable: no output, no crash, no project artifact", () => {
    // Point XDG_STATE_HOME at a plain file so mkdir -p fails — an
    // unrememberable welcome must NOT fire (it would re-fire every session).
    const blocker = join(tempDir, "not-a-dir");
    writeFileSync(blocker, "");
    const environment = gitFixtureEnv(tempDir);
    delete environment.CODEX_THREAD_ID;
    delete environment.PLUGIN_ROOT;
    environment.XDG_STATE_HOME = blocker;
    const result = Bun.spawnSync(["bash", HOOK_PATH], {
      cwd: tempDir,
      env: environment,
      stdout: "pipe",
      stderr: "pipe",
    });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString()).toBe("");
    expect(existsSync(join(tempDir, ".claude"))).toBe(false);
  });
});
