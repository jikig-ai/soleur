# Learning: worktree-manager.sh require_working_tree() false-positive in bare repo worktrees

## Problem

The `require_working_tree()` guard in `worktree-manager.sh` blocks commands like `draft-pr` when running from a worktree whose parent repository is bare. The script detects the parent repo's bare status (lines 40-49) and sets `IS_BARE=true`, but `require_working_tree()` then rejects ALL execution when `IS_BARE=true` -- even from a valid working tree inside a worktree.

This caused 8 failed attempts to run `worktree-manager.sh draft-pr` before manually running the equivalent commands.

## Solution

The `require_working_tree()` function should check `git rev-parse --is-inside-work-tree` instead of relying solely on `IS_BARE`. This returns `true` inside worktrees even when the parent repo is bare, correctly distinguishing "bare repo root" (no working tree) from "worktree of bare repo" (has working tree).

Alternatively, `require_working_tree()` could check if CWD is inside a `.worktrees/` path, since all worktrees are created there.

## Key Insight

`IS_BARE` conflates two states: "the parent repo is bare" and "we are in the bare repo root without a working tree." Functions that need a working tree should check for the working tree itself, not the repo topology.

## Tags

category: runtime-errors
module: worktree-manager
