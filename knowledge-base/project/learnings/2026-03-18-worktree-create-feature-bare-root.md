# Learning: worktree create/feature commands fail from bare repo root

## Problem

The `create` and `feature` commands in `worktree-manager.sh` fail with `fatal: this operation must be run in a work tree` when run from a bare repo root. Both functions call `require_working_tree()` as an early guard, then use `git checkout $from_branch && git pull origin $from_branch` — all working-tree operations unavailable at the bare root.

## Solution

Extracted `update_branch_ref()` helper that branches on context:
- **Bare repo root** (`IS_BARE=true && IS_IN_WORKTREE!=true`): uses `git fetch origin main:main` (refspec form, same pattern as `cleanup_merged_worktrees`)
- **Non-bare or inside worktree**: retains `git checkout && git pull`

Removed `require_working_tree` from `create_worktree()` and `create_for_feature()` since `git worktree add` works fine from bare roots. Kept it in `create_draft_pr()` which genuinely needs a working tree.

## Key Insight

`git worktree add` itself works from bare repos — only the pre-creation branch update was broken. Functions that update a branch ref should detect bare-vs-non-bare and use the appropriate primitive: `git fetch origin ref:ref` (plumbing, no working tree needed) vs `git checkout && git pull` (porcelain, requires working tree). The fix pattern already existed in the same file's `cleanup_merged_worktrees`.

## Tags
category: runtime-errors
module: plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
