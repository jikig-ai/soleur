import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync, mkdirSync, existsSync, writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

const HOOK_PATH = join(import.meta.dir, "../hooks/welcome-hook.sh");

function createTempGitRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "welcome-hook-test-"));
  // Unset git env vars so git init creates a standalone repo,
  // not one linked to the parent (lefthook sets GIT_DIR in pre-commit).
  Bun.spawnSync(
    ["bash", "-c", `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; git init "${dir}"`],
    { stdout: "ignore", stderr: "ignore" },
  );
  return dir;
}

function runHook(cwd: string): { exitCode: number; stdout: string; stderr: string } {
  // Unset git env vars so git rev-parse resolves to the temp dir,
  // not the parent repo (lefthook sets these in pre-commit context).
  const result = Bun.spawnSync(
    ["bash", "-c", `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; bash "${HOOK_PATH}"`],
    {
      cwd,
      stdout: "pipe",
      stderr: "pipe",
    },
  );
  return {
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  };
}

describe("welcome-hook project scope guard", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempGitRepo();
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  test("non-Soleur git repo: exits 0, no sentinel created", () => {
    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(existsSync(join(tempDir, ".claude", "soleur-welcomed.local"))).toBe(false);
  });

  test("git repo with plugins/soleur/ directory: creates sentinel and outputs welcome JSON", () => {
    mkdirSync(join(tempDir, "plugins", "soleur"), { recursive: true });

    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(existsSync(join(tempDir, ".claude", "soleur-welcomed.local"))).toBe(true);
    expect(result.stdout).toContain("hookSpecificOutput");
    expect(result.stdout).toContain("SessionStart");
  });

  test("Soleur project with existing sentinel: exits 0 immediately, no output", () => {
    mkdirSync(join(tempDir, "plugins", "soleur"), { recursive: true });
    mkdirSync(join(tempDir, ".claude"), { recursive: true });
    writeFileSync(join(tempDir, ".claude", "soleur-welcomed.local"), "");

    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("git repo with CLAUDE.md not referencing soleur: exits 0, no sentinel", () => {
    writeFileSync(join(tempDir, "CLAUDE.md"), "# My Project\n\nSome instructions.");

    const result = runHook(tempDir);

    expect(result.exitCode).toBe(0);
    expect(existsSync(join(tempDir, ".claude", "soleur-welcomed.local"))).toBe(false);
  });
});
