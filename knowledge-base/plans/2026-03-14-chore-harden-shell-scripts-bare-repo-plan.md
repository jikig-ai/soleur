---
title: "chore: harden remaining shell scripts for bare repo context"
type: chore
date: 2026-03-14
semver: patch
---

# chore: harden remaining shell scripts for bare repo context

## Overview

Follow-up from worktree-manager.sh bare repo fix (PR #609). 11 shell scripts use `git rev-parse --show-toplevel` with `|| pwd` or `|| "."` fallbacks. They survive in bare repo context but may resolve to incorrect paths silently -- leading to .env files being written to the wrong directory, state files being created in unexpected locations, and `cd` commands failing.

This plan covers two work streams: (1) hardening the 11 scripts with proper IS_BARE detection, and (2) fixing medium/low-priority issues in worktree-manager.sh itself identified during PR #609 review.

## Problem Statement

`git rev-parse --show-toplevel` fails with exit 128 in bare repos (`core.bare=true`). Every script using this command either crashes or silently falls back to `pwd`/`"."`, which resolves to the bare repo root -- not a valid working tree. This causes:

- `.env` files written to the bare root instead of the project root (security: secrets in an unexpected location)
- Ralph loop state files created in the wrong `.claude/` directory
- `generate-article-30-register.sh` crashes with `cd` to non-existent working tree
- Welcome hook sentinel check fails silently, re-welcoming every session

## Proposed Solution

### Approach A: Shared `resolve-git-root.sh` helper (chosen)

Extract the IS_BARE detection pattern from worktree-manager.sh into a reusable helper script at `plugins/soleur/scripts/resolve-git-root.sh`. Each script sources the helper and gets `GIT_ROOT` and `IS_BARE` variables. Benefits:

- Single source of truth for bare repo detection logic
- DRY -- fixes propagate to all consumers automatically
- Consistent behavior across all scripts
- Minimal diff per script (replace 1 line with 1 `source` line + optional guard)

### Approach B: Inline IS_BARE pattern in each script (rejected)

Copy the 7-line bare repo detection block into each script. Downside: 11 copies of the same logic that must be updated in sync.

## Technical Approach

### The shared helper (`plugins/soleur/scripts/resolve-git-root.sh`)

Exports two variables when sourced:

- `GIT_ROOT` -- absolute path to the repository root (bare or non-bare)
- `IS_BARE` -- `"true"` or `"false"`

Implementation matches the proven pattern from worktree-manager.sh lines 27-38.

### Script categories and required changes

**Category 1: Scripts that need GIT_ROOT for file paths (replace fallback)**

These scripts use `PROJECT_ROOT` or `repo_root` to locate `.env`, `.claude/`, or template files. Replace the fallback pattern with the sourced helper.

| Script | Variable | Current Pattern | Bare Behavior |
|--------|----------|----------------|---------------|
| `welcome-hook.sh` | `PROJECT_ROOT` | `|| PROJECT_ROOT="."` | Sentinel check uses `.` -- relative, fragile |
| `stop-hook.sh` | `PROJECT_ROOT` | `|| PROJECT_ROOT="."` | State file path uses `.` -- works if CWD is repo root, breaks otherwise |
| `setup-ralph-loop.sh` | `PROJECT_ROOT` | `|| PROJECT_ROOT="."` | State file created at `./.claude/` -- CWD dependent |
| `discord-setup.sh` (write-env) | `repo_root` | `\|\| pwd` | `.env` written to CWD, not repo root |
| `discord-setup.sh` (verify) | `repo_root` | `\|\| pwd` | `.env` sourced from CWD |
| `x-setup.sh` (write-env) | `repo_root` | `\|\| pwd` | `.env` written to CWD |
| `x-setup.sh` (verify) | `repo_root` | `\|\| pwd` | `.env` sourced from CWD |
| `bsky-setup.sh` (write-env) | `repo_root` | `\|\| pwd` | `.env` written to CWD |
| `bsky-setup.sh` (verify) | `repo_root` | `\|\| pwd` | `.env` sourced from CWD |

**Category 2: Scripts that `cd` to repo root (must guard or skip)**

| Script | Current Pattern | Required Change |
|--------|----------------|-----------------|
| `generate-article-30-register.sh` | `cd "$(git rev-parse --show-toplevel)"` | Use helper; guard with IS_BARE exit since the script needs a working tree to find the template |

### worktree-manager.sh improvements (from PR #609 review)

**Medium priority:**

1. **`create_draft_pr()` IS_BARE guard** -- Add `require_working_tree` call at the top of the function. `git commit --allow-empty` requires a working tree.

2. **`list_worktrees()` bare-context output** -- When IS_BARE is true, replace "Main repository" label with "Bare root (no working tree)" and suppress the `git rev-parse --abbrev-ref HEAD` call (returns misleading output).

3. **Add `.claude-plugin` to `sync_bare_files` file list** -- The plugin manifest is read by Claude Code from disk. Missing from the sync list means stale plugin config after merges.

**Low priority:**

4. **Atomic file overwrites in `sync_bare_files`** -- Write to temp file with `mktemp`, then `mv` into place. Prevents truncated files if interrupted mid-write.

5. **Consolidate `.claude/settings.json` into `files=()` array** -- Remove the dedicated 7-line block and add the path to the main array. Add `mkdir -p` logic for paths with subdirectories.

6. **Rename `sync` alias to `sync-bare`** -- The `sync` alias in the case statement shadows the Unix `sync` command. Add `sync-bare` as the primary, keep `sync` as a secondary alias with a deprecation note.

7. **Stale file cleanup in `sync_bare_files`** -- Track which hook files exist in git HEAD and remove on-disk files that no longer exist. Prevents deleted hooks from continuing to execute.

## Acceptance Criteria

- [ ] A shared `resolve-git-root.sh` helper exists at `plugins/soleur/scripts/resolve-git-root.sh`
- [ ] All 7 scripts listed in Category 1 source the helper instead of inline fallback patterns
- [ ] `generate-article-30-register.sh` uses the helper and exits cleanly in bare repo context
- [ ] `create_draft_pr()` has IS_BARE guard (calls `require_working_tree`)
- [ ] `list_worktrees()` shows "Bare root (no working tree)" instead of "Main repository" when bare
- [ ] `.claude-plugin` is in the `sync_bare_files` file list
- [ ] `sync_bare_files` uses atomic writes (mktemp + mv)
- [ ] `.claude/settings.json` is consolidated into the `files=()` array
- [ ] `sync-bare` is the documented alias (with `sync` kept for backward compat)
- [ ] Stale hook files are cleaned up during sync
- [ ] All scripts pass `set -euo pipefail` (no regressions)
- [ ] Test file `ralph-loop-stuck-detection.test.sh` still works (it mocks git rev-parse)

## Test Scenarios

- Given a bare repo root, when `welcome-hook.sh` runs, then the sentinel file is created at the correct bare root path (not `.`)
- Given a bare repo root, when `stop-hook.sh` runs with an active ralph loop, then the state file is found at the correct path
- Given a bare repo root, when `setup-ralph-loop.sh` runs, then `.claude/ralph-loop.local.md` is created under `GIT_ROOT`
- Given a bare repo root, when `discord-setup.sh write-env` runs, then `.env` is written to `GIT_ROOT`, not CWD
- Given a bare repo root, when `generate-article-30-register.sh` runs, then it exits with a clear error message (no working tree)
- Given a bare repo root, when `worktree-manager.sh draft-pr` runs, then it exits with `require_working_tree` error
- Given a bare repo root, when `worktree-manager.sh list` runs, then it shows "Bare root (no working tree)" instead of "Main repository"
- Given a bare repo root, when `worktree-manager.sh sync-bare-files` runs, then `.claude-plugin` is synced
- Given a bare repo root, when `sync_bare_files` is interrupted mid-write, then no target file is left truncated (atomic writes)
- Given a deleted hook script in git HEAD, when `sync_bare_files` runs, then the stale on-disk hook file is removed

## Non-Goals

- Refactoring scripts beyond what is needed for bare repo compatibility
- Adding bare repo support to the test file (`ralph-loop-stuck-detection.test.sh`) -- it creates its own git repo
- Changing how worktrees themselves work (worktrees have working trees by definition)
- Adding tests for the community setup scripts (they require API credentials)

## Dependencies and Risks

**Dependencies:**
- PR #609 must be merged first (provides the baseline IS_BARE pattern) -- already merged as of this plan

**Risks:**
- **Source path resolution**: `source` in the helper needs a reliable path. Since hooks and scripts are invoked from various CWD locations, the helper must resolve its own path via `BASH_SOURCE`. Mitigation: use `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` pattern in the consumer or a well-known relative path.
- **Test regression**: The ralph loop test file mocks `PROJECT_ROOT`. Switching to the sourced helper could break the mock. Mitigation: read and adapt the test file, or allow test-specific overrides.

## References

- PR #609: worktree-manager.sh bare repo hardening
- GitHub Issue: #610
- Learning: `knowledge-base/learnings/2026-03-13-bare-repo-stale-files-and-working-tree-guards.md`
- Learning: `knowledge-base/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md`
- Existing pattern: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` lines 27-38
