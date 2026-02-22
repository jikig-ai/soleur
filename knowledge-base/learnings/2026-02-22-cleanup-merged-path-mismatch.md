# Learning: cleanup-merged fails silently when branch names contain slashes

## Problem

The `worktree-manager.sh cleanup-merged` function reports "Cleaned N merged worktree(s)" but leaves worktree directories and git records intact. This caused 6 stale worktrees to accumulate across sessions despite cleanup running at every session start.

The symptom: `git worktree list` shows worktrees that `cleanup-merged` claims to have cleaned. The script deletes the branch (`git branch -D`) but never removes the worktree directory or git record.

## Root Cause

The script constructs the worktree path from the branch name:

```text
worktree_path="$WORKTREE_DIR/$branch"
```

But AGENTS.md instructs creating worktrees with hyphenated directories and slashed branch names:

```text
git worktree add .worktrees/feat-<name> -b feat/<name>
```

This creates a mismatch:

| Branch name | Script constructs | Actual directory |
|---|---|---|
| `feat/fix-agent-descriptions` | `.worktrees/feat/fix-agent-descriptions` | `.worktrees/feat-fix-agent-descriptions` |

The directory check `if [[ -d "$worktree_path" ]]` fails (the constructed path doesn't exist), so `git worktree remove` is skipped. But `git branch -D` succeeds. The script adds the branch to `cleaned[]` and reports success.

After the branch is deleted, subsequent `cleanup-merged` runs can't find it in `git for-each-ref` (the branch no longer exists), so the orphaned worktree becomes permanently invisible to the cleanup script.

## Solution

Replace the path construction with a lookup from `git worktree list --porcelain`, which provides the actual path for each branch:

```text
# Parse git worktree list --porcelain to build branch -> path map
# Each entry has: worktree <path>, HEAD <sha>, branch refs/heads/<name>
# Use an associative array: branch_to_worktree[branch]=path
```

This decouples the cleanup logic from any assumption about directory naming conventions.

Additionally: retry `git worktree remove` with `--force` on first failure, since worktrees with untracked files (e.g., from interrupted archival) fail without `--force`.

## Key Insight

Never construct filesystem paths from git ref names. Git refs use `/` as a namespace separator (e.g., `feat/fix-x`), but filesystem directories created by users or scripts may use `-` instead. Always query git for the actual path using `git worktree list --porcelain`.

A second insight: a script that reports "Cleaned N items" must verify the cleanup actually happened. Reporting success after deleting only the branch (but failing to remove the worktree) is a misleading success message.

## Session Errors

1. Manually removed `feat-coo-domain-leader` worktree that was active in another session -- had to restore branch and recreate worktree
2. `cleanup-merged` reported "Cleaned 4/5 merged worktree(s)" in two runs this session but directories persisted -- the misleading success message delayed diagnosis
3. `feat-github-dpa-verify` was skipped by cleanup due to uncommitted changes from an interrupted compound archival -- required manual `--force` removal

## Tags
category: runtime-errors
module: plugins/soleur/skills/git-worktree
symptoms: stale worktrees persist after cleanup-merged reports success
