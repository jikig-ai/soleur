# Learning: Pull latest main after cleanup-merged

## Problem
After merging a PR and running `cleanup-merged`, the main checkout stays at whatever commit it was before the merge. The next worktree creation branches from a stale main, requiring a manual `git fetch && git merge` in the new worktree.

## Solution
Added `git pull --ff-only origin main` to the `cleanup_merged_worktrees()` function in worktree-manager.sh, guarded by: (1) at least one branch was cleaned, (2) main checkout is clean, (3) graceful degradation on network failure.

## Key Insight
Post-merge lifecycle steps belong in the script (single source of truth), not just skill instructions. All callers (ship, merge-pr, session-start hygiene) get the behavior automatically. Use `--ff-only` instead of `git pull` because main should never diverge from origin/main -- a non-fast-forward failure signals a configuration error.

## Tags
category: integration-issues
module: git-worktree
