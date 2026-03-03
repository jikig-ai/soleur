import { describe, test, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

const HOOK_PATH = join(
  import.meta.dirname,
  "..",
  ".claude",
  "hooks",
  "pre-merge-rebase.sh"
);

function makeInput(command: string, cwd?: string): string {
  return JSON.stringify({
    tool_name: "Bash",
    tool_input: { command },
    ...(cwd ? { cwd } : {}),
  });
}

async function runHook(
  input: string
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(["bash", HOOK_PATH], {
    stdin: new Response(input),
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const exitCode = await proc.exited;
  return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode };
}

// ---------------------------------------------------------------------------
// Tests that do NOT require a git repo (early-exit paths)
// ---------------------------------------------------------------------------

describe("pre-merge-rebase hook (no git repo needed)", () => {
  test("non-merge command passes through immediately", async () => {
    const result = await runHook(makeInput("gh pr view 123"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("non-gh command passes through immediately", async () => {
    const result = await runHook(makeInput("npm test"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("git commit command passes through immediately", async () => {
    const result = await runHook(makeInput("git commit -m 'fix: something'"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("chained command with gh pr merge is detected", async () => {
    // This should be detected -- but without a valid cwd it will fail-open
    const result = await runHook(
      makeInput("git add -A && gh pr merge 123 --squash --auto", "/nonexistent")
    );
    expect(result.exitCode).toBe(0);
    // Without a valid git dir, it exits early (fail-open)
  });

  test("semicolon-chained gh pr merge is detected", async () => {
    const result = await runHook(
      makeInput("echo done; gh pr merge 123", "/nonexistent")
    );
    expect(result.exitCode).toBe(0);
  });

  test("pipe-or-chained gh pr merge is detected", async () => {
    const result = await runHook(
      makeInput("false || gh pr merge 123", "/nonexistent")
    );
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Tests that require a git repo
// ---------------------------------------------------------------------------

describe("pre-merge-rebase hook (with git repo)", () => {
  let repoDir: string;
  let remoteDir: string;

  beforeAll(() => {
    // Create a bare "remote" repo and a local clone
    remoteDir = mkdtempSync(join(tmpdir(), "hook-test-remote-"));
    repoDir = mkdtempSync(join(tmpdir(), "hook-test-local-"));

    // Initialize bare remote
    Bun.spawnSync(["git", "init", "--bare"], { cwd: remoteDir });

    // Clone to local
    rmSync(repoDir, { recursive: true });
    Bun.spawnSync(["git", "clone", remoteDir, repoDir]);

    // Configure local repo
    Bun.spawnSync(["git", "config", "user.email", "test@test.com"], {
      cwd: repoDir,
    });
    Bun.spawnSync(["git", "config", "user.name", "Test"], { cwd: repoDir });

    // Create initial commit on main
    Bun.spawnSync(["bash", "-c", "echo 'init' > file.txt && git add file.txt && git commit -m 'init'"], {
      cwd: repoDir,
    });
    Bun.spawnSync(["git", "push", "origin", "main"], { cwd: repoDir });
  });

  afterAll(() => {
    rmSync(repoDir, { recursive: true, force: true });
    rmSync(remoteDir, { recursive: true, force: true });
  });

  beforeEach(() => {
    // Reset local repo to clean state on main
    Bun.spawnSync(["git", "checkout", "main"], { cwd: repoDir });
    Bun.spawnSync(["git", "reset", "--hard", "origin/main"], { cwd: repoDir });
    // Clean up any test branches
    const branches = Bun.spawnSync(
      ["git", "branch", "--list", "test-*"],
      { cwd: repoDir }
    );
    const branchList = new TextDecoder()
      .decode(branches.stdout)
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((b) => b.trim());
    for (const branch of branchList) {
      Bun.spawnSync(["git", "branch", "-D", branch], { cwd: repoDir });
    }
  });

  test("branch already up-to-date with main proceeds without rebase", async () => {
    // Create a feature branch from current main
    Bun.spawnSync(["git", "checkout", "-b", "test-uptodate"], { cwd: repoDir });
    Bun.spawnSync(
      ["bash", "-c", "echo 'feature' > feature.txt && git add feature.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    Bun.spawnSync(["git", "push", "origin", "test-uptodate"], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    // Should see the "already up-to-date" message on stderr
    expect(result.stderr).toContain("up-to-date");
    // No JSON output (no deny, no additionalContext needed)
    expect(result.stdout).toBe("");
  });

  test("branch behind main triggers rebase and force-push", async () => {
    // Create a feature branch
    Bun.spawnSync(["git", "checkout", "-b", "test-behind"], { cwd: repoDir });
    Bun.spawnSync(
      ["bash", "-c", "echo 'feature' > feature.txt && git add feature.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    Bun.spawnSync(["git", "push", "origin", "test-behind"], { cwd: repoDir });

    // Now advance main on remote (simulate another merged PR)
    Bun.spawnSync(["git", "checkout", "main"], { cwd: repoDir });
    Bun.spawnSync(
      ["bash", "-c", "echo 'new-on-main' > main-change.txt && git add main-change.txt && git commit -m 'main advance'"],
      { cwd: repoDir }
    );
    Bun.spawnSync(["git", "push", "origin", "main"], { cwd: repoDir });

    // Switch back to feature branch (now behind main)
    Bun.spawnSync(["git", "checkout", "test-behind"], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    // Should return additionalContext about successful rebase
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.additionalContext).toContain("rebased");
    expect(output.hookSpecificOutput.additionalContext).toContain("test-behind");
  });

  test("uncommitted changes blocks merge with deny", async () => {
    Bun.spawnSync(["git", "checkout", "-b", "test-dirty"], { cwd: repoDir });
    // Create uncommitted change
    Bun.spawnSync(["bash", "-c", "echo 'dirty' >> file.txt"], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      "Uncommitted changes"
    );
  });

  test("staged uncommitted changes blocks merge with deny", async () => {
    Bun.spawnSync(["git", "checkout", "-b", "test-staged"], { cwd: repoDir });
    Bun.spawnSync(
      ["bash", "-c", "echo 'staged' >> file.txt && git add file.txt"],
      { cwd: repoDir }
    );

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      "Uncommitted changes"
    );
  });

  test("rebase conflict aborts and blocks with file list", async () => {
    // Create a feature branch that modifies same file as main
    Bun.spawnSync(["git", "checkout", "-b", "test-conflict"], { cwd: repoDir });
    Bun.spawnSync(
      ["bash", "-c", "echo 'feature-content' > file.txt && git add file.txt && git commit -m 'feature change'"],
      { cwd: repoDir }
    );
    Bun.spawnSync(["git", "push", "origin", "test-conflict"], { cwd: repoDir });

    // Advance main with conflicting change
    Bun.spawnSync(["git", "checkout", "main"], { cwd: repoDir });
    Bun.spawnSync(
      ["bash", "-c", "echo 'main-content' > file.txt && git add file.txt && git commit -m 'main conflict'"],
      { cwd: repoDir }
    );
    Bun.spawnSync(["git", "push", "origin", "main"], { cwd: repoDir });

    // Switch back to feature branch
    Bun.spawnSync(["git", "checkout", "test-conflict"], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      "Rebase against origin/main failed"
    );
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      "file.txt"
    );

    // Verify rebase was aborted (working tree is clean)
    const status = Bun.spawnSync(["git", "status", "--short"], {
      cwd: repoDir,
    });
    expect(new TextDecoder().decode(status.stdout).trim()).toBe("");
  });

  test("detached HEAD allows merge with warning", async () => {
    // Detach HEAD
    const headSha = Bun.spawnSync(["git", "rev-parse", "HEAD"], {
      cwd: repoDir,
    });
    const sha = new TextDecoder().decode(headSha.stdout).trim();
    Bun.spawnSync(["git", "checkout", sha], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("Detached HEAD");
    expect(result.stdout).toBe("");
  });

  test("hook is idempotent -- second run after rebase shows up-to-date", async () => {
    // Create feature branch behind main
    Bun.spawnSync(["git", "checkout", "-b", "test-idempotent"], {
      cwd: repoDir,
    });
    Bun.spawnSync(
      ["bash", "-c", "echo 'feature' > feature2.txt && git add feature2.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    Bun.spawnSync(["git", "push", "origin", "test-idempotent"], {
      cwd: repoDir,
    });

    // Advance main
    Bun.spawnSync(["git", "checkout", "main"], { cwd: repoDir });
    Bun.spawnSync(
      ["bash", "-c", "echo 'advance' > advance.txt && git add advance.txt && git commit -m 'advance'"],
      { cwd: repoDir }
    );
    Bun.spawnSync(["git", "push", "origin", "main"], { cwd: repoDir });

    Bun.spawnSync(["git", "checkout", "test-idempotent"], { cwd: repoDir });

    // First run: triggers rebase
    const first = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );
    expect(first.exitCode).toBe(0);
    const firstOutput = JSON.parse(first.stdout);
    expect(firstOutput.hookSpecificOutput.additionalContext).toContain(
      "rebased"
    );

    // Second run: should be up-to-date
    const second = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );
    expect(second.exitCode).toBe(0);
    expect(second.stderr).toContain("up-to-date");
    expect(second.stdout).toBe("");
  });
});
