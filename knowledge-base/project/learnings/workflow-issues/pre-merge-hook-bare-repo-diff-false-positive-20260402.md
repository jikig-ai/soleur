---
module: System
date: 2026-04-02
problem_type: workflow_issue
component: tooling
symptoms:
  - "BLOCKED: Uncommitted changes detected. Commit before merging."
  - "gh pr merge blocked in bare repo worktree setups even when working tree is clean"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [bare-repo, pre-merge-hook, git-diff, false-positive, worktree]
---

# Troubleshooting: pre-merge hook false positive in bare repo worktree setups

## Problem

The `pre-merge-rebase.sh` PreToolUse hook blocks `gh pr merge` with "Uncommitted changes detected" when the Bash tool's CWD is a bare repo, even though bare repos have no working tree and therefore no uncommitted changes.

## Environment

- Module: System (hooks infrastructure)
- Affected Component: `.claude/hooks/pre-merge-rebase.sh` lines 104-116
- Date: 2026-04-02

## Symptoms

- `gh pr merge` denied with "BLOCKED: Uncommitted changes detected. Commit before merging."
- Only occurs when CWD is a bare repo (not a worktree)
- Workaround was using the GraphQL API directly

## What Didn't Work

**Attempted Solution 1:** Exit-code capture approach (`DIFF_EXIT=0; git diff || DIFF_EXIT=$?` with `if [[ $DIFF_EXIT -eq 1 ]]`)

- **Why it failed:** Works for `git diff --quiet HEAD` (returns exit 128 in bare repos, correctly filtered by `-eq 1`), but `git diff --cached --quiet` returns exit **1** in bare repos (empty index differs from HEAD), which is indistinguishable from "genuinely staged changes." The plan prescribed this approach, but empirical testing revealed the `--cached` asymmetry.

## Session Errors

**Plan prescribed wrong approach (exit-code capture) that failed for `diff --cached`**

- **Recovery:** Pivoted to `rev-parse --is-inside-work-tree` guard after discovering `diff --cached` returns 1 in bare repos
- **Prevention:** When a plan prescribes a fix based on exit code semantics, empirically verify ALL commands' exit codes (not just the primary one) before implementing. Plans document assumed behavior; tests verify actual behavior.

**Test setup failed: missing git user config in bare repo**

- **Recovery:** Added `-c user.email=test@test.com -c user.name=Test` flags to bare repo git commands
- **Prevention:** When creating git commits in test fixtures with `GIT_CONFIG_GLOBAL=/dev/null`, always provide user identity via `-c` flags or env vars.

**Test passed vacuously (false green) -- Guard 6 denied before diff check**

- **Recovery:** Planted review evidence in bare repo via filesystem `todos/` directory
- **Prevention:** When testing a specific code path in a multi-guard hook, verify the test actually reaches that code path. A test that passes because an earlier guard fires is a false green.

**Test passed vacuously again -- `rev-parse --abbrev-ref HEAD` returns "HEAD" for non-existent refs**

- **Recovery:** Created actual ref with `git update-ref` before changing symbolic HEAD
- **Prevention:** In bare repos, `git rev-parse --abbrev-ref HEAD` returns literal "HEAD" when the target ref has no commits. Always create the target ref before setting symbolic HEAD.

**Review agents identified weak assertion (silent pass anti-pattern)**

- **Recovery:** Replaced conditional assertion with direct `expect(result.stdout).toBe("")`
- **Prevention:** Never use conditional assertions (`if (output) { expect(...) }`) where the happy path makes the condition false. The assertion never executes on the happy path, providing zero regression protection.

## Solution

Wrap the diff check in a work-tree guard that skips the check entirely in bare repo contexts:

**Code changes:**

```bash
# Before (broken):
if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
   ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
  # deny...
fi

# After (fixed):
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
     ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
    # deny...
  fi
fi
```

## Why This Works

1. **Root cause:** `git diff --quiet HEAD` returns exit 128 in bare repos (no work tree) and `git diff --cached --quiet` returns exit 1 (empty index vs HEAD). The hook's `if ! git diff` pattern treats both as "dirty," causing false positives.

2. **Why the fix works:** `git rev-parse --is-inside-work-tree` returns `"true"` only in actual work trees (including worktrees). In bare repos it returns `"false"` with exit 0. By guarding the diff check, we skip it entirely when there's no work tree to check. The concepts of "dirty tree" and "staged changes" are meaningless in a bare repo.

3. **Why not exit-code capture:** The plan's preferred approach (`|| DIFF_EXIT=$?` with `-eq 1` check) only works for `diff --quiet HEAD` (exit 128). It fails for `diff --cached --quiet` which returns exit 1 in bare repos -- indistinguishable from genuinely staged changes.

## Prevention

- When writing hooks that use `git diff`, always consider bare repo contexts where diff commands return unexpected exit codes
- Use `rev-parse --is-inside-work-tree` as a guard before any git command that requires a working tree
- Test hooks with bare repo fixtures, not just regular repos
- The `rev-parse --is-inside-work-tree` check returns "false" with exit 0 -- check the output string, not the exit code

## Related Issues

- See also: [pre-merge-hook-false-positive-on-string-content](../2026-03-19-pre-merge-hook-false-positive-on-string-content.md) -- different false positive (string matching), same hook
- See also: [2026-03-18-worktree-manager-bare-repo-false-positive](../2026-03-18-worktree-manager-bare-repo-false-positive.md) -- related bare repo detection issue
- GitHub issue: #1386
- Related PR: #1389 (core.bare bleed fix)
