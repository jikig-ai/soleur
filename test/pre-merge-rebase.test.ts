import { describe, test, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, chmodSync, existsSync, unlinkSync } from "fs";
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
  let initialMainSha: string;
  // Per-suite directory holding the `gh` stub that replaces the live GitHub
  // CLI during Signal 3 review-evidence lookups. Isolates the hook from
  // GitHub API wall-clock variance that previously pushed CI past the 5s
  // bun-test default (#2801).
  let binDir: string;
  let ghCalledSentinel: string;

  beforeAll(() => {
    remoteDir = mkdtempSync(join(tmpdir(), "hook-test-remote-"));
    repoDir = mkdtempSync(join(tmpdir(), "hook-test-local-"));
    binDir = mkdtempSync(join(tmpdir(), "hook-test-bin-"));
    ghCalledSentinel = join(binDir, ".gh-called");

    // Write a deterministic `gh` stub. The hook's Signal 3 path only invokes
    // `gh issue list --label code-review ...` when `gh pr merge <N>` includes a
    // literal PR number (PR_NUMBER is extracted from argv at pre-merge-rebase.sh
    // PR_NUMBER extraction step, so the `gh pr list` fallback is unreachable
    // from these tests). The stub echoes an empty jq result -> hook treats it
    // as "no review issue found" -> deny, matching the pre-stub behavior when
    // the live API returned no match.
    const ghStub = `#!/usr/bin/env bash
# Test stub for \`gh\` — pre-merge-rebase.test.ts Signal 3 isolation (#2801).
# Reachable invocations:
#   gh issue list --label code-review --state all --search "PR #N" --limit 1 --json number --jq '.[0].number // empty'
# Return empty stdout so the hook's \`// empty\` jq default fires and REVIEW_ISSUES stays empty.
# The sentinel file proves the stub was consulted (see sentinel expects in the two Signal-3 tests).
touch "$(dirname "$0")/.gh-called"
case "$1 $2" in
  "issue list"|"pr list")
    exit 0
    ;;
  *)
    # Unexpected invocation: warn visibly but don't fail the hook (fail-open
    # semantics match the hook's real \`2>/dev/null || true\` pattern).
    echo "[test stub] unexpected gh invocation: $*" >&2
    exit 0
    ;;
esac
`;
    const ghPath = join(binDir, "gh");
    writeFileSync(ghPath, ghStub);
    chmodSync(ghPath, 0o755);

    // Extend GIT_ENV.PATH so the stub wins PATH resolution for any Bun.spawn
    // inside this describe block. The const binding is fine — we're mutating
    // the object's property, not rebinding the variable.
    (GIT_ENV as Record<string, string>).PATH = `${binDir}:${cleanEnv.PATH ?? ""}`;

    // PATH sanity: fail fast if the stub doesn't win resolution.
    const whichGh = new TextDecoder()
      .decode(Bun.spawnSync(["which", "gh"], { env: GIT_ENV }).stdout)
      .trim();
    expect(whichGh).toBe(ghPath);

    spawnChecked(["git", "init", "--bare", "--initial-branch=main"], { cwd: remoteDir });

    rmSync(repoDir, { recursive: true });
    spawnChecked(["git", "clone", remoteDir, repoDir], { cwd: tmpdir() });

    spawnChecked(["git", "config", "user.email", "test@test.com"], { cwd: repoDir });
    spawnChecked(["git", "config", "user.name", "Test"], { cwd: repoDir });

    spawnChecked(["bash", "-c", "echo 'init' > file.txt && git add file.txt && git commit -m 'init'"], {
      cwd: repoDir,
    });
    spawnChecked(["git", "push", "origin", "main"], { cwd: repoDir });

    initialMainSha = new TextDecoder()
      .decode(spawnChecked(["git", "rev-parse", "main"], { cwd: repoDir }).stdout)
      .trim();
  });

  afterAll(() => {
    rmSync(repoDir, { recursive: true, force: true });
    rmSync(remoteDir, { recursive: true, force: true });
    rmSync(binDir, { recursive: true, force: true });
  });

  beforeEach(() => {
    // Reset per-test sentinel so each test asserts a fresh stub invocation.
    if (existsSync(ghCalledSentinel)) unlinkSync(ghCalledSentinel);
    spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
    // Reset remote main to initial commit so tests that pushed to origin/main
    // don't affect subsequent tests (latent ordering dependency).
    spawnChecked(
      ["git", "update-ref", "refs/heads/main", initialMainSha],
      { cwd: remoteDir }
    );
    // Re-fetch so local origin/main tracks the reset remote.
    spawnChecked(["git", "fetch", "origin"], { cwd: repoDir });
    // Re-reset local main to match the now-reset origin/main.
    spawnChecked(["git", "reset", "--hard", "origin/main"], { cwd: repoDir });
    // Remove untracked files/directories (e.g., todos/ from addReviewEvidence).
    // git reset --hard only resets tracked files; clean -fd handles the rest.
    spawnChecked(["git", "clean", "-fd"], { cwd: repoDir });
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
    expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("");
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      "No review evidence"
    );
    // Proves the hook's Signal 3 path reached the PATH-prefix gh stub instead of
    // the live GitHub CLI. If CI's /usr/local/bin/gh ever wins PATH resolution,
    // this fails loudly rather than reintroducing wall-clock flake (#2801).
    expect(existsSync(ghCalledSentinel), "gh stub was not consulted during Signal 3 review-issue lookup").toBe(true);
  }, 15000);

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

  test("todos-only review evidence satisfies review evidence gate", async () => {
    spawnChecked(["git", "checkout", "-b", "test-review-todos"], { cwd: repoDir });
    spawnChecked(
      ["bash", "-c", "echo 'feature' > feature.txt && git add feature.txt && git commit -m 'feature'"],
      { cwd: repoDir }
    );
    // Add review evidence via todos file only (no matching commit message)
    spawnChecked(
      ["bash", "-c", "mkdir -p todos && echo 'tags: code-review' > todos/review-finding.md && git add todos/ && git commit -m 'chore: add review todos'"],
      { cwd: repoDir }
    );
    spawnChecked(["git", "push", "origin", "test-review-todos"], { cwd: repoDir });

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
    expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("");
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
    expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("");
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
    expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("");
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
    expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("");
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

  test("detached HEAD allows merge with warning (review gate fires first)", async () => {
    // Create a feature branch with review evidence, then detach HEAD.
    // The review gate fires before the detached HEAD exit because
    // gh pr merge operates on a PR number, not the local checkout state.
    spawnChecked(["git", "checkout", "-b", "test-detached-review"], { cwd: repoDir });
    addReviewEvidence(repoDir);
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

  test("detached HEAD without review evidence is denied", async () => {
    // Precondition: verify no review evidence leaked from prior tests.
    // Without this, a leaked todos/ directory causes a silent false-green
    // (hook finds evidence, skips deny, test gets empty stdout, JSON.parse throws).
    const todosCheck = Bun.spawnSync(["test", "-d", "todos"], {
      cwd: repoDir, env: GIT_ENV,
    });
    expect(todosCheck.exitCode, "todos/ must NOT exist — review evidence leaked from a prior test").not.toBe(0);

    const headSha = spawnChecked(["git", "rev-parse", "HEAD"], { cwd: repoDir });
    const sha = new TextDecoder().decode(headSha.stdout).trim();
    Bun.spawnSync(["git", "checkout", sha], { cwd: repoDir, env: GIT_ENV });

    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe("deny");
    // See sentinel comment on the sibling "no review evidence" test above.
    expect(existsSync(ghCalledSentinel), "gh stub was not consulted during Signal 3 review-issue lookup").toBe(true);
  }, 15000);

  test("main branch skips sync silently", async () => {
    const result = await runHook(
      makeInput("gh pr merge 123 --squash --auto", repoDir)
    );

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("bare repo cwd does not false-positive on uncommitted changes", async () => {
    // remoteDir is already a bare repo (created in beforeAll) with commits
    // on main (pushed in beforeAll). Create test-feature branch pointing to
    // the same commit so rev-parse --abbrev-ref HEAD returns "test-feature"
    // (not literal "HEAD" which triggers the detached HEAD exit).
    const mainSha = new TextDecoder().decode(
      spawnChecked(["git", "rev-parse", "main"], { cwd: remoteDir }).stdout
    ).trim();
    spawnChecked(
      ["git", "update-ref", "refs/heads/test-feature", mainSha],
      { cwd: remoteDir }
    );
    spawnChecked(
      ["git", "symbolic-ref", "HEAD", "refs/heads/test-feature"],
      { cwd: remoteDir }
    );

    // Add review evidence via filesystem todos/ directory so Guard 6 passes.
    // Bare repos have no working tree, but the grep -rl check on $WORK_DIR/todos/
    // just reads regular files at that path — works regardless of bare status.
    mkdirSync(join(remoteDir, "todos"), { recursive: true });
    writeFileSync(join(remoteDir, "todos", "review.md"), "tags: code-review\n");

    try {
      const result = await runHook(
        makeInput("gh pr merge 123 --squash --auto", remoteDir)
      );

      expect(result.exitCode).toBe(0);
      // Hook must pass through without any deny — bare repo context skips
      // the work-tree-only diff check entirely. Empty stdout = no deny output.
      expect(result.stdout).toBe("");
    } finally {
      // Restore HEAD to main and clean up
      spawnChecked(
        ["git", "symbolic-ref", "HEAD", "refs/heads/main"],
        { cwd: remoteDir }
      );
      Bun.spawnSync(
        ["git", "update-ref", "-d", "refs/heads/test-feature"],
        { cwd: remoteDir, env: GIT_ENV }
      );
      rmSync(join(remoteDir, "todos"), { recursive: true, force: true });
    }
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
      expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("");
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
    expect(first.stdout, "expected JSON deny output but got empty stdout").not.toBe("");
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
