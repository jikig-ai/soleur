# Learning: Worktree cleanup gap after mid-session PR merge

## Problem

After merging a PR with `gh pr merge` during an active Claude Code session, the worktree and local branch were not cleaned up automatically. The user had to manually run worktree removal.

## Symptoms

- Worktree directory still exists in `.worktrees/` after PR is merged
- Local branch still exists even though remote branch was deleted
- `git worktree list` shows stale worktree

## Root Cause

The `cleanup-merged` script (which detects `[gone]` branches and removes their worktrees) was only wired into two triggers:

1. **SessionStart hook** -- fires when a new Claude Code session starts
2. **`/soleur:work` Phase 0** -- fires when starting new work

Neither triggers when a PR is merged mid-session. The `/ship` skill ended at Phase 7 (PR creation) with no post-merge step.

## Solution

Added Phase 8 to `/ship` skill that:

1. Offers to merge the PR immediately after creation
2. Runs `cleanup-merged` after merge to remove the worktree, archive specs, and delete the local branch
3. Falls back gracefully -- if user merges later or via GitHub UI, SessionStart hook catches it next session

## Key Insight

When building lifecycle workflows with hooks, map every state transition and verify each one has a cleanup trigger. The hook coverage had a gap at the "merge" transition because `/ship` was designed to stop at PR creation, treating merge as a separate concern. But in practice, users often merge immediately after shipping.

## Tags

category: workflow-issues
module: git-worktree, ship
symptoms: worktree not cleaned after merge, stale worktree, gone branch
