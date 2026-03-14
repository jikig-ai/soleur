# Learning: Bare repos have two failure modes -- stale on-disk files and unguarded working-tree commands

## Problem

After release 3.18.8 fixed GIT_ROOT detection for bare repos (`2026-03-13-bare-repo-git-rev-parse-failure.md`), `worktree-manager.sh` still failed with "fatal: this operation must be run in a work tree" in three code paths:

1. **cleanup_merged epilogue** -- called `git diff`, `git checkout main`, `git pull --ff-only` against `$GIT_ROOT`, all requiring a working tree
2. **create_worktree / create_for_feature** -- called `git checkout` to switch base branch before `git worktree add`
3. **Stale on-disk files** -- bare repos never update on-disk files after merges, so AGENTS.md, CLAUDE.md, hooks, and the script itself were perpetually outdated

Root cause: category error assuming "GIT_ROOT exists" implies "a working tree exists at GIT_ROOT." In bare repos, GIT_ROOT is a git object store, not a checked-out tree.

## Solution

Four changes guarded by a single `IS_BARE` flag computed once at script init:

1. **IS_BARE flag** -- consolidated with existing `git rev-parse --is-bare-repository` check (no extra subprocess)
2. **Guard cleanup_merged epilogue** -- skip `git diff`/`checkout`/`pull` when bare, auto-call `sync_bare_files` instead
3. **`require_working_tree()` helper** -- exits with clear error message, called from both create functions
4. **`sync-bare-files` subcommand** -- extracts critical files from `git HEAD` via `git show`, overwrites stale copies, restores permissions

## Key Insight

Bare repo + worktree workflows have a **two-layer failure model**: (1) git plumbing commands work fine but working-tree commands crash, and (2) on-disk files at the bare root drift from git HEAD after every merge. Fixing one layer without the other leaves the system broken. The sync-bare-files pattern (extract from git, overwrite on disk) is the canonical solution for layer 2 -- but layer 1 (IS_BARE guards) must come first or the sync code itself crashes.

## Session Errors

- `worktree-manager.sh cleanup-merged` crash at session start (exit 128) -- the bug being fixed
- CWD left at bare root after testing sync-bare-files, required manual switch back to worktree

## Prevention

- When writing shell scripts that use git commands, audit each command against the bare-repo compatibility table (git fetch/for-each-ref/worktree-list work; git diff/checkout/pull/status don't)
- Test scripts from both worktree context AND bare repo root context
- For bare repo workflows, add a `sync` mechanism for any files that tools read from disk rather than from git

## Tags
category: build-errors
module: git-worktree
