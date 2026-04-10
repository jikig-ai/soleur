# Learning: Worktree creation can silently fail while reporting success

## Problem

Running `worktree-manager.sh --yes create byok-cost-tracking` reported `✓ Worktree created successfully!` but the worktree was not registered in `git worktree list`. The directory existed with files (from the script's `mkdir -p` and dependency install steps) but had no `.git` file, making all git commands fail with `fatal: this operation must be run in a work tree`.

## Solution

1. Removed the broken directory: `rm -rf .worktrees/byok-cost-tracking`
2. Deleted the orphaned branch: `git branch -D byok-cost-tracking`
3. Re-ran the creation script — second attempt succeeded and appeared in `git worktree list`

## Key Insight

A post-creation verification step was added to `worktree-manager.sh` in #1806, but this session hit the bug anyway. The likely cause: the bare repo root has no working tree, so the script invoked from the bare root may have been a stale copy predating #1806. This is analogous to the `.mcp.json` refresh issue — bare repos require manual sync of scripts used from the root.

A secondary error compounded the issue: running `git add` repeatedly instead of diagnosing why git commands failed. When git says "must be run in a work tree," verify `.git` file existence in the target directory before retrying.

## Session Errors

**Worktree creation silent failure** — The script printed success but `git worktree add` silently failed. Recovery: deleted directory, deleted branch, re-ran script. Prevention: Add a post-creation verification step to `worktree-manager.sh` that checks `git worktree list` contains the new path before printing success.

**Repeated bare-repo git commands** — Ran `git add` 6 times from bare repo root before diagnosing the CWD issue. Recovery: checked `pwd`, discovered CWD was correct but `.git` was missing due to the silent failure above. Prevention: On first `fatal: this operation must be run in a work tree`, immediately check for `.git` file existence rather than retrying.

## Tags

category: integration-issues
module: git-worktree
