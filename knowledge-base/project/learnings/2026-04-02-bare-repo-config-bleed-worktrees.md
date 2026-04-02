---
module: System
date: 2026-04-02
problem_type: configuration
component: git-worktree
symptoms:
  - "git rev-parse --is-bare-repository returns true inside worktrees"
  - "git rev-parse --is-inside-work-tree returns false inside worktrees"
  - "git commit fails with 'fatal: this operation must be run in a work tree'"
  - "git push fails from worktree"
  - "worktree-manager.sh commands fail or produce wrong output"
root_cause: repositoryformatversion_mismatch
resolution_type: config_fix
severity: critical
tags: [git, bare-repo, worktree, extensions.worktreeConfig, repositoryformatversion]
---

# Learning: Bare repo config bleed breaks all git worktrees

## Problem

The Soleur repository is a bare git repo (`core.bare=true`) that uses git worktrees
for all development. After configuration changes, `core.bare=true` in the shared
`.git/config` started bleeding into all worktrees, making every working-tree operation
fail with "fatal: this operation must be run in a work tree."

## Root Cause

Three conditions combined to create the failure:

1. `.git/config` had `extensions.worktreeConfig = true` -- intended to allow
   per-worktree config overrides
2. `.git/config` had `repositoryformatversion = 0` -- the default for most repos
3. `.git/config` had `core.bare = true` -- correct for the bare root

Git silently ignores ALL `extensions.*` settings when `repositoryformatversion` is 0.
The `extensions.worktreeConfig = true` setting was inert, so `core.bare=true` in the
shared config was read by every worktree. Each worktree believed it was a bare repo
and refused all working-tree operations.

This is particularly insidious because `git config --get extensions.worktreeConfig`
returns `true` -- the value is there, it just has no effect at format version 0.

## Solution

Three git config changes (no code changes needed for the core fix):

```bash
# 1. Enable Git to read extensions.* settings
git config --file .git/config core.repositoryformatversion 1

# 2. Remove core.bare from shared config (all worktrees were reading it)
git config --file .git/config --unset core.bare

# 3. Create per-worktree config so only the bare root sees itself as bare
echo -e "[core]\n\tbare = true" > .git/config.worktree
```

After these changes:

- Bare root: reads `core.bare=true` from `.git/config.worktree` -- correct
- Worktrees: do not see `core.bare` at all -- correct (they are not bare)

Defense-in-depth: Updated `worktree-manager.sh` with an `ensure_bare_config()`
function that auto-detects and fixes the broken state on every invocation.

## Session Errors

### 1. worktree-manager `draft-pr` failed from bare root

`worktree-manager.sh draft-pr` failed because `git` commands inside the script
saw `core.bare=true` and refused to operate.

**Prevention:** The `ensure_bare_config()` guard now runs at script entry. It checks
`repositoryformatversion` and `core.bare` placement, fixing them before any git
operations execute.

### 2. `git commit` and `git push` failed in worktrees

All commits and pushes failed with "fatal: this operation must be run in a work tree"
because worktrees inherited `core.bare=true`.

**Prevention:** Same root fix -- `repositoryformatversion=1` makes
`extensions.worktreeConfig` effective, and moving `core.bare` to
`.git/config.worktree` scopes it to the bare root only.

### 3. `gh pr create` failed (no commits)

PR creation failed because no commits could be made (downstream of error 2).

**Prevention:** Upstream fix resolves this. Always investigate root cause of
cascading failures rather than retrying downstream commands.

### 4. Worktree created at wrong path

`worktree-manager.sh create` placed the worktree at an incorrect path because
`GIT_ROOT` detection was confused by the bare state. When `core.bare=true` bleeds
into a worktree, `git rev-parse --git-dir` returns unexpected values.

**Prevention:** The `ensure_bare_config()` guard normalizes the config before
path resolution runs, ensuring `GIT_ROOT` is computed correctly.

### 5. `list` showed "No worktrees found"

`worktree-manager.sh list` reported no worktrees even when they existed. The script
used `-d .git` to detect whether it was inside a git repo, but worktrees have a
`.git` **file** (not a directory) pointing to the parent repo.

**Prevention:** Changed `-d .git` to `-e .git` in the detection logic. `-e` matches
both files and directories, correctly handling both the bare root (`.git` directory)
and worktrees (`.git` file).

### 6. Scripts ran stale bare-root copies

Running `../../plugins/soleur/skills/.../worktree-manager.sh` from a worktree
resolved to the bare repo's on-disk files, which are stale in a bare repo (the bare
root has no working tree, so files on disk may not match any branch).

**Prevention:** Always run scripts from the worktree's own file tree, not via
relative paths that resolve to the bare root. Use `$(git rev-parse --show-toplevel)`
to anchor paths when needed.

## Diagnostic Commands

When suspecting bare config bleed, run these from inside a worktree:

```bash
# Should return false in a worktree
git rev-parse --is-bare-repository

# Should return true in a worktree
git rev-parse --is-inside-work-tree

# Check format version (must be 1 for extensions to work)
git config --file "$(git rev-parse --git-common-dir)/config" \
  core.repositoryformatversion

# Check where core.bare is defined
git config --show-origin core.bare
```

## Key Insight

When using a bare git repo with worktrees, `extensions.worktreeConfig=true` requires
`repositoryformatversion=1` to take effect. Without it, `core.bare=true` bleeds from
the shared config into all worktrees, breaking every working-tree operation. Git
provides no warning -- the extension setting is silently ignored at format version 0.

## Tags

category: configuration
module: git, git-worktree
symptoms: bare config bleed, worktree sees bare=true, this operation must be run in a work tree
