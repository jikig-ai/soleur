# Learning: Worktree discipline -- always edit in the worktree

## Problem

While working on a Telegram bridge feature with an active git worktree at `.worktrees/telegram-bridge/`, edits were applied to files in the main repo root instead of the worktree directory. When the session resumed, all changes were lost -- the edits existed only as uncommitted modifications on the main branch that got discarded. The worktree had an older committed version, leaving no trace of the work.

Additionally, feature-scoped directories like `todos/` were created at the repo root instead of inside the app directory within the worktree.

## Solution

When a git worktree exists for the current feature branch:

1. **All edits must be made in the worktree directory**, not the repo root
2. **Feature-scoped directories** (todos, reports, etc.) belong inside the app directory within the worktree (e.g., `apps/telegram-bridge/todos/`), not at repo root
3. **Verify location before writing**: run `pwd` and check for `.worktrees/<name>/` in the path

Signs of editing the wrong location:
- `pwd` shows the main repo root, not `.worktrees/<name>/`
- `git status` in the worktree doesn't show your changes
- Feature-specific directories appear at repo root

## Key Insight

Git worktrees create isolated working directories but the filesystem doesn't prevent editing the wrong one. Uncommitted work in the wrong location is invisible to both the worktree and the main branch, making it unrecoverable once the session ends. Treat worktree location verification as a mandatory gate before any file write.

## Related

- [Worktree cleanup gap after merge](../2026-02-09-worktree-cleanup-gap-after-merge.md) -- post-merge cleanup automation
- AGENTS.md "Worktree Awareness" section -- existing rules that should have been followed

## Tags
category: workflow-patterns
module: git-worktree
symptoms: changes lost, edits in wrong directory, uncommitted work disappeared
