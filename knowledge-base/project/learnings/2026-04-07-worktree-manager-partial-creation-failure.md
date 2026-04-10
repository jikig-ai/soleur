# Learning: worktree-manager.sh can create directory without proper git worktree

## Problem

Running `worktree-manager.sh feature start-fresh-onboarding` from the bare repo root appeared to succeed (printed "Feature setup complete!" with green checkmarks) but produced only a directory containing `knowledge-base/` — not a functioning git worktree. Inside the directory, `git rev-parse --show-toplevel` failed with "this operation must be run in a work tree" and `git branch --show-current` returned `main` (the bare repo's HEAD).

The `draft-pr` subcommand also failed because `plugins/` doesn't exist inside worktrees — the script path `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` is only valid from the bare repo root. Using relative path `../../plugins/...` triggered the script's own "Cannot run from bare repo root" guard.

## Solution

Removed the broken directory and recreated the worktree directly:

```bash
rm -rf .worktrees/feat-start-fresh-onboarding
git worktree add .worktrees/feat-start-fresh-onboarding -b feat-start-fresh-onboarding main
```

This produced a proper worktree with correct `git branch --show-current` output.

## Key Insight

The worktree-manager.sh script's success output is not a reliable indicator of actual worktree creation. When the script reports success but the worktree doesn't function, the fallback is `git worktree add` directly. Always verify with `git branch --show-current` after creation. The `draft-pr` subcommand needs to be invoked from inside a working worktree, not from the bare root using relative paths.

## Session Errors

- **Worktree partial creation** — Recovery: manual `rm -rf` + `git worktree add`. Prevention: add a post-creation verification step to the worktree-manager.sh script that runs `git rev-parse --show-toplevel` and fails loudly if it doesn't match the expected path.
- **draft-pr path resolution** — Recovery: skipped draft-pr for this session. Prevention: worktree-manager.sh should resolve its own script path dynamically rather than requiring the caller to know where `plugins/` lives.

## Tags

category: integration-issues
module: plugins/soleur/skills/git-worktree
