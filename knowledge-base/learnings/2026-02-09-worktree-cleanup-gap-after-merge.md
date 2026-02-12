# Learning: Worktree cleanup gap after mid-session PR merge

## Problem

After merging a PR with `gh pr merge` during an active Claude Code session, the worktree and local branch were not cleaned up automatically. The user had to manually run worktree removal.

## Symptoms

- Worktree directory still exists in `.worktrees/` after PR is merged
- Local branch still exists even though remote branch was deleted
- `git worktree list` shows stale worktree

## Root Cause

Two independent issues compound to prevent cleanup:

**Issue 1 (trigger gap):** The `cleanup-merged` script was only wired into two triggers:

1. **SessionStart hook** -- fires when a new Claude Code session starts
2. **`/soleur:work` Phase 0** -- fires when starting new work

Neither triggers when a PR is merged mid-session. The `/ship` skill ended at Phase 7 (PR creation) with no post-merge step.

**Issue 2 (prerequisite gap):** [Updated 2026-02-12] The `cleanup-merged` script relies on `git fetch --prune` to detect `[gone]` branches. But GitHub only deletes the remote branch on merge if the repo has `delete_branch_on_merge=true`. With this setting disabled (the default), the remote branch persists after merge, `fetch --prune` has nothing to prune, and `cleanup-merged` never sees a `[gone]` branch -- even when triggered correctly.

## Solution

**Fix 1 (trigger):** Added Phase 8 to `/ship` skill that:

1. Offers to merge the PR immediately after creation
2. Runs `cleanup-merged` after merge to remove the worktree, archive specs, and delete the local branch
3. Falls back gracefully -- if user merges later or via GitHub UI, SessionStart hook catches it next session

**Fix 2 (prerequisite):** [Updated 2026-02-12] Enable `delete_branch_on_merge` on the GitHub repo:

```bash
gh api repos/<owner>/<repo> -X PATCH -f delete_branch_on_merge=true
```

This is a one-time setting. Without it, `cleanup-merged` can never detect merged branches automatically.

## Key Insight

When building lifecycle workflows with hooks, map every state transition and verify each one has a cleanup trigger. The hook coverage had a gap at the "merge" transition because `/ship` was designed to stop at PR creation, treating merge as a separate concern. But in practice, users often merge immediately after shipping.

[Updated 2026-02-12] Cleanup scripts that depend on external state (like GitHub deleting remote branches) must verify their prerequisites are met. The `cleanup-merged` script silently did nothing because its prerequisite (`delete_branch_on_merge=true`) was never checked or enforced.

## Tags

category: workflow-issues
module: git-worktree, ship
symptoms: worktree not cleaned after merge, stale worktree, gone branch
