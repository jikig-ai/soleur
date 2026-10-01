# Learning: Transport deltas, not whole files, across worktrees

category: workflow-patterns
module: git-worktree
date: 2026-09-23

## Problem

A ledger edit began in a detached checkout whose `HEAD` lagged `origin/main`. Copying the whole
edited file into a fresh worktree briefly removed a newer expense row that existed only on the
fresh branch. `git diff` caught the deletion before commit.

## Root cause

The intended change was one added row, but the transfer unit was the entire file. A whole-file
copy carries the source checkout's omissions along with its intended edits.

## Prevention

When moving uncommitted work to a worktree based on a newer ref, extract and apply the narrow diff
against the destination file. Immediately inspect the destination diff for unrelated deletions or
modifications before making further edits. If a whole-file copy was already made, restore the file
from the destination `HEAD` and reapply only the intended hunk.

## Tags

category: workflow-patterns
module: git-worktree
