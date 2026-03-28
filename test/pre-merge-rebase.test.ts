import { describe, test, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import { mkdtempSync, rmSync, chmodSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

const HOOK_PATH = join(
  import.meta.dirname,
  "..",
  ".claude",
  "hooks",
  "pre-merge-rebase.sh"
);

// Strip git hook env vars (GIT_DIR, GIT_INDEX_FILE, GIT_WORK_TREE) that
// git sets when running pre-commit hooks — these override GIT_CEILING_DIRECTORIES
// and cause tests to use the parent repo instead of the temp repos.
const {
  GIT_DIR: _d,
  GIT_INDEX_FILE: _i,
  GIT_WORK_TREE: _w,
  ...cleanEnv
} = process.env;
const GIT_ENV = {
  ...cleanEnv,
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CEILING_DIRECTORIES: tmpdir(),
};

function makeInput(command: string, cwd?: string): string {
  return JSON.stringify({
    tool_name: "Bash",
    tool_input: { command },
    ...(cwd ? { cwd } : {}),
  });
}

function spawnChecked(args: string[], opts: { cwd: string }) {
  const result = Bun.spawnSync(args, { ...opts, env: GIT_ENV });
  if (result.exitCode !== 0) {
    const stderr = new TextDecoder().decode(result.stderr);
    throw new Error(`Setup failed: ${args.join(" ")} exited ${result.exitCode}: ${stderr}`);
  }
  return result;
}

/**
 * Create review evidence so Guard 6 (review evidence gate) passes.
 * Must be called after creating a feature branch and before running the hook.
 */
function addReviewEvidence(cwd: string) {
  spawnChecked(
    ["bash", "-c", "mkdir -p todos && echo 'tags: code-review' > todos/review-finding.md && git add todos/ && git commit -m 'refactor: add code review findings'"],
    { cwd }
  );
}

async function runHook(
  input: string
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(["bash", HOOK_PATH], {
    stdin: new Response(input),
    stdout: "pipe",
    stderr: "pipe",
    env: GIT_ENV,
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
    expect(result.stderr).toBe("");
  });

  test("non-gh command passes through immediately", async () => {
    const result = await runHook(makeInput("npm test"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
    expect(result.stderr).toBe("");
  });

  test("git commit command passes through immediately", async () => {
    const result = await runHook(makeInput("git commit -m 'fix: something'"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
    expect(result.stderr).toBe("");
  });

  test("gh pr merge-request does not trigger hook (word boundary)", async () => {
    const result = await runHook(makeInput("gh pr merge-request 123"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
    expect(result.stderr).toBe("");
  });

  test("chained command with gh pr merge is detected", async () => {
    // Detected but fails-open due to /nonexistent cwd
    const result = await runHook(
      makeInput("git add -A && gh pr merge 123 --squash --auto", "/nonexistent")
    );
    expect(result.exitCode).toBe(0);
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
    remoteDir = mkdtempSync(join(tmpdir(), "hook-test-remote-"));
    repoDir = mkdtempSync(join(tmpdir(), "hook-test-local-"));

    spawnChecked(["git", "init", "--bare", "--initial-branch=main"], { cwd: remoteDir });

    rmSync(repoDir, { recursive: true });
    spawnChecked(["git", "clone", remoteDir, repoDir], { cwd: tmpdir() });

    spawnChecked(["git", "config", "user.email", "test@test.com"], { cwd: repoDir });
    spawnChecked(["git", "config", "user.name", "Test"], { cwd: repoDir });

    spawnChecked(["bash", "-c", "echo 'init' > file.txt && git add file.txt && git commit -m 'init'"], {
      cwd: repoDir,
    });
    spawnChecked(["git", "push", "origin", "main"], { cwd: repoDir });
  });

  afterAll(() => {
    rmSync(repoDir, { recursive: true, force: true });
    rmSync(remoteDir, { recursive: true, force: true });
  });

  beforeEach(() => {
    spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
    spawnChecked(["git", "reset", "--hard", "origin/main"], { cwd: repoDir });
    const branches = Bun.spawnSync(["git", "branch", "--list", "test-*"], {
      cwd: repoDir,
      env: GIT_ENV,
    });
    const branchList = new TextDecoder()
      .decode(branches.stdout)
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((b) => b.trim());
    for (const branch of branchList) {
      Bun.spawnSync(["git", "branch", "-D", branch], { cwd: repoDir, env: GIT_ENV });
    }
  });

  test("no review evidence blocks merge with deny", async () => {
    spawnChecked(["git", "checkout", "-b", "test-no-review"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'feature' > feature.txt && git add feature.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      "No review evidence"
    );
  });

  test("review commit message satisfies review evidence gate", async () => {
    spawnChecked(["git", "checkout", "-b", "test-review-commit"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'feature' > feature.txt && git add feature.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    // Add review evidence via commit message (no todos/ directory)
    spawnChecked(
      ["bash", "-c", "echo 'reviewed' > reviewed.txt && git add reviewed.txt && git commit -m 'refactor: add code review findings'"],
      { cwd: repoDir }
    );
    spawnChecked(["git", "push", "origin", "test-review-commit"], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    // Should pass the review gate and reach the up-to-date check
    expect(result.stderr).toContain("up-to-date");
  });

  test("branch already up-to-date with main proceeds without sync", async () => {
    spawnChecked(["git", "checkout", "-b", "test-uptodate"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'feature' > feature.txt && git add feature.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    addReviewEvidence(repoDir);
    spawnChecked(["git", "push", "origin", "test-uptodate"], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("up-to-date");
    expect(result.stdout).toBe("");
  });

  test("branch behind main triggers merge and push", async () => {
    spawnChecked(["git", "checkout", "-b", "test-behind"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'feature' > feature.txt && git add feature.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    addReviewEvidence(repoDir);
    spawnChecked(["git", "push", "origin", "test-behind"], { cwd: repoDir });

    spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'new-on-main' > main-change.txt && git add main-change.txt && git commit -m 'main advance'"],
      { cwd: repoDir }
    );
    spawnChecked(["git", "push", "origin", "main"], { cwd: repoDir });

    spawnChecked(["git", "checkout", "test-behind"], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.additionalContext).toContain("merged");
    expect(output.hookSpecificOutput.additionalContext).toContain("test-behind");
  });

  test("uncommitted changes blocks merge with deny", async () => {
    spawnChecked(["git", "checkout", "-b", "test-dirty"], { cwd: repoDir });
    addReviewEvidence(repoDir);
    Bun.spawnSync(["bash", "-c", "echo 'dirty' >> file.txt"], { cwd: repoDir, env: GIT_ENV });

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
    spawnChecked(["git", "checkout", "-b", "test-staged"], { cwd: repoDir });
    addReviewEvidence(repoDir);
    Bun.spawnSync(
      ["bash", "-c", "echo 'staged' >> file.txt && git add file.txt"],
      { cwd: repoDir, env: GIT_ENV }
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

  test("merge conflict aborts and blocks with file list", async () => {
    spawnChecked(["git", "checkout", "-b", "test-conflict"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'feature-content' > file.txt && git add file.txt && git commit -m 'feature change'"],
      { cwd: repoDir }
    );
    addReviewEvidence(repoDir);
    spawnChecked(["git", "push", "origin", "test-conflict"], { cwd: repoDir });

    spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'main-content' > file.txt && git add file.txt && git commit -m 'main conflict'"],
      { cwd: repoDir }
    );
    spawnChecked(["git", "push", "origin", "main"], { cwd: repoDir });

    spawnChecked(["git", "checkout", "test-conflict"], { cwd: repoDir });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      "Merge of origin/main failed"
    );
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      "file.txt"
    );

    // Verify merge was aborted (working tree is clean)
    const status = Bun.spawnSync(["git", "status", "--short"], {
      cwd: repoDir,
      env: GIT_ENV,
    });
    expect(new TextDecoder().decode(status.stdout).trim()).toBe("");
  });

  test("detached HEAD allows merge with warning", async () => {
    const headSha = spawnChecked(["git", "rev-parse", "HEAD"], { cwd: repoDir });
    const sha = new TextDecoder().decode(headSha.stdout).trim();
    Bun.spawnSync(["git", "checkout", sha], { cwd: repoDir, env: GIT_ENV });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("Detached HEAD");
    expect(result.stdout).toBe("");
  });

  test("main branch skips sync silently", async () => {
    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("push failure after merge blocks with deny", async () => {
    spawnChecked(["git", "checkout", "-b", "test-pushfail"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'feature' > pushfail.txt && git add pushfail.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    addReviewEvidence(repoDir);
    spawnChecked(["git", "push", "origin", "test-pushfail"], { cwd: repoDir });

    spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'advance' > advance2.txt && git add advance2.txt && git commit -m 'advance'"],
      { cwd: repoDir }
    );
    spawnChecked(["git", "push", "origin", "main"], { cwd: repoDir });

    spawnChecked(["git", "checkout", "test-pushfail"], { cwd: repoDir });

    // Break only the push URL so fetch still works but push fails.
    // This simulates a network error on push without affecting fetch.
    spawnChecked(["git", "remote", "set-url", "--push", "origin", "/nonexistent-remote"], { cwd: repoDir });

    try {
      const result = await runHook(
        makeInput("gh pr merge 123 --squash --auto", repoDir)
      );

      expect(result.exitCode).toBe(0);
      const output = JSON.parse(result.stdout);
      expect(output.hookSpecificOutput.permissionDecision).toBe("deny");
      expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
        "push failed"
      );
    } finally {
      // Restore push URL and abort any merge state
      spawnChecked(["git", "remote", "set-url", "--push", "origin", remoteDir], { cwd: repoDir });
      Bun.spawnSync(["git", "merge", "--abort"], { cwd: repoDir, env: GIT_ENV });
    }
  });

  test("hook is idempotent -- second run after merge shows up-to-date", async () => {
    spawnChecked(["git", "checkout", "-b", "test-idempotent"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'feature' > feature2.txt && git add feature2.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    addReviewEvidence(repoDir);
    spawnChecked(["git", "push", "origin", "test-idempotent"], { cwd: repoDir });

    spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'advance' > advance.txt && git add advance.txt && git commit -m 'advance'"],
      { cwd: repoDir }
    );
    spawnChecked(["git", "push", "origin", "main"], { cwd: repoDir });

    spawnChecked(["git", "checkout", "test-idempotent"], { cwd: repoDir });

    // First run: triggers merge
    const first = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );
    expect(first.exitCode).toBe(0);
    const firstOutput = JSON.parse(first.stdout);
    expect(firstOutput.hookSpecificOutput.additionalContext).toContain("merged");

    // Second run: should be up-to-date
    const second = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );
    expect(second.exitCode).toBe(0);
    expect(second.stderr).toContain("up-to-date");
    expect(second.stdout).toBe("");
  });
});
