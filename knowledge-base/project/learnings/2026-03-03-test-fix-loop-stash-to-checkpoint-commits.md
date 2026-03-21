---
title: Replace git stash with checkpoint commits for worktree-safe rollback
date: 2026-03-03
category: workflow-patterns
tags: [integration-issues, test-fix-loop]
---

# Learning: Replace git stash with checkpoint commits for worktree-safe rollback

## Problem

The test-fix-loop skill used `git stash push` to save working-tree state before each fix attempt and `git stash pop` / `git stash drop` to restore or discard it on iteration boundaries. This directly conflicts with two project hard rules:

- AGENTS.md: "Never `git stash` in worktrees. Commit WIP first, then merge."
- constitution.md: stash is prohibited in worktrees due to the catastrophic worktree loss incident documented in `knowledge-base/project/learnings/2026-02-22-worktree-loss-stash-merge-pop.md`.

The skill was written before the stash prohibition was established, so the violation was not caught at authoring time. Because the stash operations were embedded in SKILL.md prose (not executable scripts), no hook could block them at runtime -- the agent simply followed the documented instructions.

## Solution

Replace every stash operation with a checkpoint commit pattern:

1. **Save state (was `git stash push`):** `git add -A && git commit -m "test-fix-loop: checkpoint iteration N"`
2. **Discard checkpoint on success (was `git stash drop`):** Not needed -- the checkpoint commit is simply left in history or squashed at session end.
3. **Revert single iteration (was `git stash pop` after failure):** `git reset --hard HEAD` reverts uncommitted changes back to the last checkpoint commit.
4. **Full revert to initial state (circular/non-convergence/max-iterations reached):** Capture `initial_sha=$(git rev-parse HEAD)` before Phase 1 begins, then `git reset --hard <initial-sha>` to restore the branch to its pre-skill state.

The `git reset --hard <sha>` with a captured SHA pattern already exists in the merge-pr skill, establishing project precedent. The migration preserves identical rollback semantics while being worktree-safe.

## Key Insight

Any skill that needs "save state / attempt change / conditionally revert" semantics must express that as checkpoint commits plus `git reset --hard`, not as stash operations. Stash is not just discouraged -- it is categorically prohibited in worktrees because a stash pop conflict can silently destroy the entire worktree linkage, with no recovery path. Checkpoint commits are always recoverable: every committed state is reachable by SHA, the reflog preserves it, and `git reset --hard` is deterministic. The two patterns are semantically equivalent for rollback purposes; only one is safe in a worktree context.

When auditing skills for worktree compliance, search for `git stash` anywhere in SKILL.md files, not just in shell scripts -- the agent executes prose instructions verbatim.

## Tags

category: integration-issues
module: test-fix-loop
