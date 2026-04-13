# Learning: worktree-manager.sh origin/main fallback leaves local main stale

## Problem

When `git fetch origin main:main` fails in a bare repo (e.g., because `main` is checked
out in another worktree), the `update_branch_ref()` fallback ran `git fetch origin main`
which only updates `origin/main` and `FETCH_HEAD` — the local `main` ref stayed stale.
Worktrees created afterward were based on the stale commit, missing recently merged PRs.

## Solution

Added `git update-ref refs/heads/$branch origin/$branch` in the `elif` fallback path.
This force-syncs the local ref to match the remote. Safe because direct commits to main
are prohibited (hook-enforced). Applied to both `update_branch_ref()` and
`cleanup_merged_worktrees()` for consistency. Added error guards on the `update-ref`
calls to surface failures instead of printing misleading success messages.

## Key Insight

In bare repos with multiple worktrees, `git fetch origin branch:branch` fails when the
target branch is checked out in any worktree — git refuses to update a ref that has a
working tree attached. The fallback `git fetch origin branch` only updates the
remote-tracking ref (`origin/branch`), not the local ref (`refs/heads/branch`). The
`git update-ref` command bypasses the checkout check because it operates on refs directly
without touching any working tree.

## Session Errors

1. **Worktree creation with long branch name silently failed** — Script reported success
   but the worktree did not appear in `git worktree list`. **Prevention:** Validate
   worktree exists after creation by checking `git worktree list` output.

2. **cd to non-existent worktree path** — Attempted to cd into a path the script printed
   but the directory did not exist. **Prevention:** Always verify worktree path via
   `git worktree list` before cd.

3. **Bare repo CWD drift** — Shell CWD silently reverted to bare repo root between Bash
   calls, causing `git branch --show-current` to return `main` unexpectedly.
   **Prevention:** Use absolute paths or re-cd at the start of each Bash call when
   working in worktrees.

## Tags

category: integration-issues
module: git-worktree
