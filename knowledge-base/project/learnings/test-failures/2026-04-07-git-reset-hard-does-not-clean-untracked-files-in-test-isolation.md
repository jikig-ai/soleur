---
module: System
date: 2026-04-07
problem_type: test_failure
component: testing_framework
symptoms:
  - "Intermittent test failure: detached HEAD without review evidence is denied"
  - "JSON.parse error on empty stdout when hook returns no deny output"
  - "Test passes when it should fail — silent false-green from leaked state"
root_cause: test_isolation
resolution_type: test_fix
severity: medium
tags: [git-clean, git-reset-hard, test-isolation, untracked-files, beforeeach]
---

# Troubleshooting: git reset --hard does not clean untracked files in test beforeEach

## Problem

The pre-merge-rebase hook test "detached HEAD without review evidence is denied" failed intermittently because `git reset --hard` in `beforeEach` does not remove untracked files or directories. A `todos/` directory created by `addReviewEvidence()` in a prior test persisted, causing the hook to find review evidence and skip the deny — a silent false-green.

## Environment

- Module: System (pre-merge-rebase hook test suite)
- Affected Component: `test/pre-merge-rebase.test.ts` beforeEach cleanup
- Date: 2026-04-07

## Symptoms

- Test "detached HEAD without review evidence is denied" fails intermittently
- When failing, `result.stdout` is empty (hook found evidence and allowed merge)
- `JSON.parse(result.stdout)` throws `SyntaxError: Unexpected end of JSON input`
- Failure depends on test execution order (which prior test ran `addReviewEvidence()`)

## What Didn't Work

**Direct solution:** The problem was identified through code analysis on the first attempt. Three failure modes were investigated; Failure Mode 1 (untracked `todos/` directory leak) was confirmed as the root cause. Failure Modes 2 and 3 were ruled out by code analysis.

## Session Errors

**Worktree disappeared after creation (3 times)**

- **Recovery:** Recreated worktree with shorter name and direct `git worktree add` command
- **Prevention:** When parallel Claude sessions run `cleanup-merged`, worktrees from other sessions can be removed. Create worktrees quickly and begin work immediately, or use unique naming to avoid false-positive cleanup matches.

**GitHub API connection resets (transient)**

- **Recovery:** Retried commands after brief pause
- **Prevention:** Transient network issue — no prevention needed beyond retry logic already in place.

## Solution

Two changes to `test/pre-merge-rebase.test.ts`:

**1. Added `git clean -fd` to `beforeEach` (line 165):**

```typescript
// Before (incomplete cleanup):
beforeEach(() => {
  spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
  spawnChecked(["git", "reset", "--hard", "origin/main"], { cwd: repoDir });
  // ... branch cleanup ...
});

// After (complete cleanup):
beforeEach(() => {
  spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
  spawnChecked(["git", "reset", "--hard", "origin/main"], { cwd: repoDir });
  // Remove untracked files/directories (e.g., todos/ from addReviewEvidence).
  // git reset --hard only resets tracked files; clean -fd handles the rest.
  spawnChecked(["git", "clean", "-fd"], { cwd: repoDir });
  // ... branch cleanup ...
});
```

**2. Added precondition assertion to the failing test (line 389):**

```typescript
test("detached HEAD without review evidence is denied", async () => {
  // Precondition: verify no review evidence leaked from prior tests.
  const todosCheck = Bun.spawnSync(["test", "-d", "todos"], {
    cwd: repoDir, env: GIT_ENV,
  });
  expect(todosCheck.exitCode, "todos/ must NOT exist — review evidence leaked from a prior test").not.toBe(0);
  // ... existing test code ...
});
```

## Why This Works

1. **Root cause:** `git reset --hard` restores the index and working tree to match the target commit, but it only operates on *tracked* files. Untracked files and directories (like `todos/` created during test setup) are left untouched. This is by design in git.

2. **Why `git clean -fd` fixes it:** The `-f` (force) flag allows deletion, and `-d` includes untracked directories. Together with `git reset --hard`, this provides a complete working tree reset — tracked files restored, untracked files removed.

3. **Why the precondition assertion helps:** Even with the cleanup fix, a future regression could re-introduce state leakage. The precondition converts a cryptic `JSON.parse` error into an actionable diagnostic message that immediately identifies the cause.

## Prevention

- Always pair `git reset --hard` with `git clean -fd` in test cleanup hooks that use shared mutable git state across tests
- Add precondition assertions to tests that depend on clean state — especially when the failure mode is a silent false-green rather than a loud failure
- When tests create files in directories not tracked by git (like `todos/`), verify the cleanup step removes them

## Related Issues

- See also: [pre-merge-hook-bare-repo-diff-false-positive-20260402.md](../workflow-issues/pre-merge-hook-bare-repo-diff-false-positive-20260402.md) — false-green anti-pattern in the same hook test file
- See also: [2026-03-24-git-ceiling-directories-test-isolation.md](../2026-03-24-git-ceiling-directories-test-isolation.md) — prior test isolation fix for GIT_CEILING_DIRECTORIES in this same test file
