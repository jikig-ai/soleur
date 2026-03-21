# Learning: Worktree creation requires absolute path from bare root

## Problem

Running `git worktree add .worktrees/feat-name -b feat/name` from a CWD inside an existing worktree creates a nested worktree at `.worktrees/existing-worktree/.worktrees/feat-name` instead of at the bare repo root. The relative path resolves from CWD, not from the git root.

## Solution

Always use absolute paths when creating worktrees from a bare repo:

```bash
git worktree add /absolute/path/to/repo/.worktrees/feat-name -b feat/name origin/main
```

Or navigate to the bare repo root first. The `worktree-manager.sh` script handles this correctly, but manual `git worktree add` commands are susceptible.

## Key Insight

In bare repos, `git worktree add` with relative paths resolves from CWD, not from `GIT_DIR`. When CWD is inside another worktree, this creates nested worktrees that are difficult to clean up. Always use absolute paths or delegate to `worktree-manager.sh`.

## Tags

category: integration-issues
module: git-worktree
