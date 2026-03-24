# Learning: GIT_CEILING_DIRECTORIES prevents test isolation failures in worktrees

## Problem

Two test files (`test/pre-merge-rebase.test.ts` and `apps/web-platform/test/workspace.test.ts`) failed when run via global `bun test` from a git worktree. Git operations in `/tmp` subdirectories traversed upward, discovered the parent worktree's `.git` directory, and either corrupted the worktree's git state or caused setup failures. Additionally, the lefthook `bun-test` pre-commit hook ran `bun test` globally instead of the sequential `scripts/test-all.sh` runner, triggering Bun's FPE crash under high subprocess spawn counts.

## Solution

Three fixes, with Fix 3 as the primary:

1. **`test/pre-merge-rebase.test.ts`**: Added `GIT_CEILING_DIRECTORIES: tmpdir()` to the existing `GIT_ENV` constant. This prevents git from traversing above `/tmp` to discover the parent repo. The `tmpdir` import was already present.

2. **`apps/web-platform/test/workspace.test.ts`**: Added `process.env.GIT_CEILING_DIRECTORIES = tmpdir()` at the top of the file (before imports). Since `provisionWorkspace` uses `execFileSync` without an explicit `env` parameter, it inherits `process.env`.

3. **`lefthook.yml`**: Changed `run: bun test` to `run: bash scripts/test-all.sh` in the `bun-test` pre-commit hook. This aligns the hook with `package.json`'s test script and CI, both of which already use the sequential runner.

## Key Insight

`GIT_CEILING_DIRECTORIES` alone is insufficient when tests run as part of a git pre-commit hook. Git sets `GIT_DIR`, `GIT_INDEX_FILE`, and `GIT_WORK_TREE` in the hook's environment, and these override `GIT_CEILING_DIRECTORIES` — `GIT_DIR` explicitly tells git which repo to use, bypassing directory traversal entirely. Tests must strip all three hook-injected vars in addition to setting `GIT_CEILING_DIRECTORIES`.

The fix has two layers: (1) `GIT_CEILING_DIRECTORIES` prevents upward traversal in standalone runs, and (2) stripping `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_WORK_TREE` prevents hook-injected vars from overriding discovery. Both are needed because tests run in both contexts (manual and as part of lefthook pre-commit hooks).

## Session Errors

1. **Wrong script path for setup-ralph-loop.sh** — Used `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` (nonexistent), corrected to `./plugins/soleur/scripts/setup-ralph-loop.sh`. **Prevention:** The one-shot skill instruction should use the correct path; verify paths exist before invoking.

2. **Planning subagent did not return required format** — The subagent completed successfully but didn't output the `## Session Summary` heading in the expected format. Required fallback to `git show` to locate the plan file. **Prevention:** Subagent return contracts should include explicit format validation or the orchestrator should gracefully handle format deviations (which it did).

## Tags

category: test-failures
module: test-infrastructure
