---
synced_to: [ship]
---

# Learning: Never use --delete-branch with parallel worktrees

## Problem

After merging a PR with `gh pr merge --squash --delete-branch`, the guardrails hook blocked the command even though the feature's worktree had already been removed. Another unrelated worktree (`feat-functional-overlap-check`) was still active.

The original AGENTS.md instruction was misleading: "Never `gh pr merge --delete-branch` while a worktree exists **for that branch**" -- implying it was safe if the specific feature's worktree was gone.

## Solution

The guardrails hook (`guardrails.sh`) checks if **any** worktree exists, not just the one for the branch being merged. In parallel development with multiple features in flight, there will almost always be other worktrees active.

The correct merge pattern is:
1. `gh pr merge <number> --squash` (never `--delete-branch`)
2. `cleanup-merged` handles both worktree removal and branch deletion safely

## Key Insight

Never use `--delete-branch` with `gh pr merge` -- period. It's not a conditional rule based on the current feature's worktree state. The guardrails hook enforces a blanket block whenever any worktree is detected, which is the correct behavior for parallel development.

## Tags
category: workflow
module: git-worktrees
symptoms: "BLOCKED: --delete-branch with active worktrees will orphan them"
