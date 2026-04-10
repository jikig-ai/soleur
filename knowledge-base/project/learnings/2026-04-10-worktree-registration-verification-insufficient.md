# Learning: git worktree rev-parse verification is insufficient for bare repo creation

## Problem

`worktree-manager.sh` verified worktree creation using only `git -C "$path" rev-parse --show-toplevel`. This check passes when the directory exists and contains a valid `.git` file pointing to the parent repo, but does NOT verify that git's internal worktree list includes the entry. On bare repos, `git worktree add` can create the directory and `.git` file but fail to register the worktree in `.git/worktrees/<name>/`, resulting in a phantom worktree that passes rev-parse but is invisible to `git worktree list`.

## Solution

Added a two-stage verification:

1. `rev-parse --show-toplevel` — confirms directory is a valid git working tree
2. `git worktree list --porcelain | grep -qxF "worktree $path"` — confirms worktree is registered

On registration failure, attempt `git worktree repair "$path"` (targeted, not global) before giving up. This repair step recovers the common case where the `.git/worktrees/<name>/gitdir` file is missing or corrupt.

Used `grep -qxF` (exact full-line match) instead of `grep -qF` (substring) to prevent prefix false positives (e.g., `.worktrees/foo` matching `.worktrees/foo-bar`).

## Key Insight

`rev-parse --show-toplevel` and `git worktree list` verify different things. The first checks directory-level validity (is this a git working tree?). The second checks registration-level validity (does git know about this worktree?). Both must pass for a worktree to be fully functional. Always verify both after `git worktree add` on bare repos.

## Session Errors

1. **Ralph loop setup script path wrong** — Tried `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` (doesn't exist), corrected to `./plugins/soleur/scripts/setup-ralph-loop.sh`. **Prevention:** The one-shot skill instruction should use an absolute path or variable for the script location.
2. **shellcheck not installed** — Non-blocking, fell back to `bash -n` syntax check. **Prevention:** Add shellcheck to dev dependencies or document it as optional in constitution.md.

## Tags

category: integration-issues
module: worktree-manager
