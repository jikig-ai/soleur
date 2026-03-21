---
title: "fix: bare repo on-disk files are stale, causing worktree-manager.sh cleanup-merged to fail"
type: fix
date: 2026-03-13
---

# fix: Bare Repo On-Disk Files Are Stale, Causing worktree-manager.sh cleanup-merged to Fail

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 5
**Research sources:** repo audit (12 shell scripts checked), 3 institutional learnings, git bare repo behavior analysis

### Key Improvements

1. Discovered secondary failure: `cleanup_merged_worktrees` "update main" block calls `git diff`, `git checkout`, `git pull` which all fail in bare repo context
2. Identified `.claude/settings.json` allow rule using `$(git rev-parse --show-toplevel)` -- another bare-repo-sensitive path
3. Found 11 other shell scripts using `git rev-parse --show-toplevel` with `|| pwd` or `|| "."` fallbacks -- these survive but may resolve to wrong paths
4. Incorporated shell-script defensive patterns from institutional learnings (trap cleanup, catch-all dispatchers)
5. Identified that the `IS_BARE` check should be computed once at script init and reused, not re-evaluated per function

### New Considerations Discovered

- The `git fetch --prune`, `git for-each-ref`, and `git worktree list --porcelain` commands all work correctly in bare repo context -- only working-tree operations (`diff`, `checkout`, `pull`) need guarding
- `git rev-parse --abbrev-ref HEAD` works in bare repos (returns `main`) -- `list_worktrees` line 241 is safe
- Part A (sync stale on-disk files) should also sync `.claude/settings.json` and any hook scripts that may have diverged

## Overview

`worktree-manager.sh cleanup-merged` fails with `fatal: this operation must be run in a work tree` when invoked from the bare repo root. The fix from commit dc60e90 is in git HEAD but the on-disk files at the bare repo root are stale -- bare repos (`core.bare=true`) have no working tree, so git never updates on-disk files. Claude Code reads CLAUDE.md/AGENTS.md from disk, not from git, so the session-start instruction in the stale on-disk AGENTS.md still says "from the repo root" and points to the stale on-disk script.

## Problem Statement

### Root Cause

Soleur uses `core.bare=true` to prevent accidental commits to main. All work happens in worktrees. This means:

1. **On-disk files at the bare repo root are frozen** at whatever state they were when `core.bare` was set. Git never updates them because there is no working tree checkout.
2. **Claude Code reads AGENTS.md from disk.** The stale on-disk AGENTS.md (line 28) says: `At session start, from the repo root: run bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.
3. **The stale on-disk worktree-manager.sh** still has `GIT_ROOT=$(git rev-parse --show-toplevel)` (no bare-repo detection), which fails immediately with exit code 128.

### Research Insights

**Verified git command behavior in bare repos:**

| Command | Works in bare repo? | Notes |
|---------|---------------------|-------|
| `git fetch --prune` | Yes | Network-only operation |
| `git for-each-ref` | Yes | Reads from refs/ directly |
| `git worktree list --porcelain` | Yes | Lists worktree metadata |
| `git rev-parse --abbrev-ref HEAD` | Yes | Returns symbolic ref |
| `git rev-parse --is-bare-repository` | Yes | Returns "true" |
| `git rev-parse --absolute-git-dir` | Yes | Returns git dir path |
| `git branch -D <branch>` | Yes | Operates on refs/ |
| `git rev-parse --show-toplevel` | **No** | Requires working tree |
| `git diff --quiet HEAD` | **No** | Requires working tree |
| `git checkout <branch>` | **No** | Requires working tree |
| `git pull --ff-only` | **No** | Requires working tree |
| `git status --porcelain` | **No** | Requires working tree |

**Implication:** The core `cleanup-merged` logic (fetch, find gone branches, remove worktrees, delete branches) works fine in bare repos. Only the "update main checkout" epilogue and the "uncommitted changes" safety check need guarding.

### What's Already Fixed in Git HEAD (But Stale on Disk)

- **AGENTS.md** (git HEAD line 29): Updated to say "from any active worktree (not the bare repo root)" with relative path `../../plugins/soleur/...`
- **worktree-manager.sh** (git HEAD lines 20-29): Bare repo detection via `git rev-parse --is-bare-repository`

### Additional Problems in cleanup_merged_worktrees When Run From Bare Repo

Even with the GIT_ROOT fix, the "update main checkout" section (lines 509-526) calls commands that require a working tree:

- **Line 511:** `git -C "$GIT_ROOT" diff --quiet HEAD` -- fails in bare repo (exit 128)
- **Line 511:** `git -C "$GIT_ROOT" diff --cached --quiet` -- fails in bare repo (exit 128)
- **Line 517:** `git -C "$GIT_ROOT" checkout main` -- fails in bare repo (exit 128)
- **Line 520:** `git -C "$GIT_ROOT" pull --ff-only origin main` -- fails in bare repo (exit 128)

In a bare repo, there is no "main checkout" to update. These must be guarded.

**Also note:** Line 443-449 checks `git -C "$worktree_path" status --porcelain` for uncommitted changes in worktrees. This is safe because worktrees themselves ARE working trees, even when the parent repo is bare. The `-C` targets the worktree path, not the bare root.

### Edge Case: `.claude/settings.json` Allow Rule

`.claude/settings.json` line 8 contains:

```
"Bash(bash $(git rev-parse --show-toplevel)/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh *)"
```

This is a Claude Code permission allow-rule pattern. If Claude Code evaluates the `$(...)` subshell when matching, it would fail in bare repo context. However, this is likely treated as a string pattern by the matcher, not shell-expanded. This should be verified but is a secondary concern.

## Proposed Solution

A two-pronged approach: (A) sync the stale on-disk files to match git HEAD, and (B) harden the script so it never breaks even if invoked from a bare repo root in the future.

### Part A: Sync Stale On-Disk Files

Use `git show HEAD:<path>` to extract the current versions from git and overwrite the stale on-disk copies. This is a one-time manual operation (the user will need to run these commands from the bare repo root):

```bash
cd /home/jean/git-repositories/jikig-ai/soleur
git show HEAD:AGENTS.md > AGENTS.md
git show HEAD:CLAUDE.md > CLAUDE.md
git show HEAD:plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh > plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
chmod +x plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
```

**Limitation:** These files will become stale again after the next merge to main. This is inherent to bare repos. Part B makes the script resilient regardless.

### Research Insights: Automating Stale File Sync

**Best Practice:** Rather than a one-time manual sync, add a `sync-bare-files` subcommand to worktree-manager.sh itself. This command would:

1. Check if `core.bare=true`
2. Extract key files from git HEAD using `git show HEAD:<path>`
3. Overwrite on-disk copies
4. Restore file permissions

This makes the sync repeatable and discoverable. It could also be called automatically at the end of `cleanup-merged` when bare is detected, ensuring on-disk files stay current after each merge cycle.

**Files to sync (critical for Claude Code operation):**

- `AGENTS.md` -- session-start instructions, hard rules
- `CLAUDE.md` -- references AGENTS.md
- `plugins/soleur/AGENTS.md` -- plugin-specific rules
- `plugins/soleur/CLAUDE.md` -- plugin instructions
- `.claude/settings.json` -- permission allow rules, hooks config
- `.claude/hooks/*.sh` -- PreToolUse hooks (guardrails, write-guard, pre-merge-rebase)
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- the script itself

**Anti-pattern to avoid:** Do NOT sync all files. Only sync files that Claude Code reads from disk at the bare repo root. Script files, skill definitions, and agent definitions are read from worktree paths, not the bare root.

### Part B: Harden worktree-manager.sh for Bare Repo Context

1. **Compute `IS_BARE` once at script initialization** and store in a global variable. Avoid calling `git rev-parse --is-bare-repository` multiple times in different functions.

```bash
# At script init (after GIT_ROOT detection)
IS_BARE=false
[[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && IS_BARE=true
```

2. **Guard the "update main checkout" section** in `cleanup_merged_worktrees`: Skip the entire `git diff`, `git checkout`, `git pull` block when `IS_BARE=true`. There is no working tree to update.

3. **Guard other working-tree-dependent operations:** Audit complete (see below).

### Research Insights: Full Script Audit Results

**Functions audited for bare-repo safety:**

| Function | Bare-safe? | Issue | Action |
|----------|-----------|-------|--------|
| GIT_ROOT detection (lines 20-29) | Yes | Already guarded | None |
| `ensure_gitignore()` | Low risk | Only called from `create_worktree`/`create_for_feature` which are interactive and never invoked from bare root via session-start | None needed |
| `copy_env_files()` | Low risk | Only called from create functions | None needed |
| `create_worktree()` (line 127: `git checkout`) | **Not bare-safe** | `git checkout "$from_branch"` fails in bare repo | Add early exit with message: "Cannot create worktrees from bare repo root. Run from a worktree or non-bare checkout." |
| `create_for_feature()` (line 177: `git checkout`) | **Not bare-safe** | Same as above | Same guard |
| `list_worktrees()` (line 241: `git rev-parse --abbrev-ref HEAD`) | Yes | Verified: returns `main` in bare repo | None |
| `cleanup_worktrees()` | Yes | Uses `$PWD` and `git worktree remove`, both safe | None |
| `cleanup_merged_worktrees()` (lines 509-526) | **Not bare-safe** | `git diff`, `git checkout`, `git pull` | Guard with `IS_BARE` check |
| `create_draft_pr()` (line 536: `git rev-parse --abbrev-ref HEAD`) | Yes | Works in bare repo | None |

**Only 3 functions need guarding.** The two `create_*` functions and the `cleanup_merged_worktrees` epilogue.

### Part C: Prevent Future Staleness (Session-Start Resilience)

The AGENTS.md session-start instruction already directs running from a worktree (in git HEAD). But as defense-in-depth:

1. **Add a comment block** at the top of worktree-manager.sh explaining the bare-repo-stale-file problem, so future editors understand why the bare detection exists.

2. **Self-healing warning** (lightweight, not full sync): When the script detects `IS_BARE=true`, compare `$0`'s hash against `git show HEAD:$relative_path` hash. If they differ, print:

```
Warning: On-disk script is stale (bare repo). Run 'worktree-manager.sh sync-bare-files' to update.
```

This is cheap (one `git show` + hash compare) and only triggers in bare contexts.

### Research Insights: Institutional Learnings Applied

From `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`:

1. **Always include a catch-all in dispatchers (Learning #5).** The `main()` case statement already has a `*` catch-all that calls `show_help`. A new `sync-bare-files` subcommand should be added to this dispatcher.

2. **Validate parameters before operations (Learning #4).** The `IS_BARE` check is effectively a parameter validation at init time -- fail fast before attempting operations that require a working tree.

From `knowledge-base/project/learnings/2026-03-13-archive-kb-stale-path-resolution.md`:

3. **Silent failures are worse than loud failures.** The original bug caused a fatal error (loud), which is actually better than the path-staleness bugs that silently skipped artifacts. The fix should preserve loud failure for truly unexpected cases while gracefully skipping known-impossible operations (like updating a main checkout that doesn't exist).

From `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md`:

4. **Guard main() with BASH_SOURCE check** for testability. Currently worktree-manager.sh has no tests. While adding tests is out of scope for this fix, adding the `BASH_SOURCE` guard now makes future testing possible without refactoring:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "${args[@]+"${args[@]}"}"
fi
```

## Acceptance Criteria

- [x] `worktree-manager.sh cleanup-merged` succeeds when invoked from the bare repo root (exit 0, no fatal errors)
- [x] `worktree-manager.sh cleanup-merged` succeeds when invoked from a worktree (existing behavior preserved)
- [x] The "update main checkout" section is skipped (with informational message) when `core.bare=true`
- [x] On-disk files at bare repo root match git HEAD after fix is applied
- [x] AGENTS.md session-start instruction works regardless of which copy (disk or git) Claude Code reads
- [x] `IS_BARE` is computed once at init, not re-evaluated per function call
- [x] `create_worktree` and `create_for_feature` exit early with clear message when invoked from bare repo

## Test Scenarios

- Given `core.bare=true` and stale on-disk files, when `cleanup-merged` runs from bare repo root, then it exits 0 with no fatal errors and cleans up any [gone] branches
- Given `core.bare=true` with no [gone] branches, when `cleanup-merged` runs from bare repo root, then it exits 0 silently (non-TTY) or prints "No merged branches" (TTY)
- Given a worktree context, when `cleanup-merged` runs, then existing behavior is unchanged (branches cleaned, specs archived, main updated)
- Given `core.bare=true`, when `cleanup-merged` finds [gone] branches, then it skips the "update main checkout" block (no `git checkout`, `git pull`) and prints a message that bare repos cannot auto-update
- Given `core.bare=true`, when `create_worktree` or `create_for_feature` is invoked, then the script exits early with a clear message about bare repo limitations
- Given `core.bare=true`, when `list_worktrees` is invoked, then it succeeds and shows worktree list (verified: `git rev-parse --abbrev-ref HEAD` works in bare repos)

### Edge Cases

- **No worktrees exist:** `cleanup-merged` should still succeed (no `.worktrees/` directory to scan)
- **All worktrees are active (current PWD):** Skip all, clean nothing, exit 0
- **Worktree has uncommitted changes:** `git -C "$worktree_path" status --porcelain` works because the worktree IS a working tree. This is safe even when the parent is bare.
- **Network unavailable:** `git fetch --prune` failure is already handled (returns 0 with warning). Bare repo adds no new failure mode here.
- **Script invoked via absolute path from worktree CWD:** The git commands use CWD-relative context. If CWD is a worktree but the script file is from bare root, `git rev-parse --is-bare-repository` returns false (worktree is not bare). This means the stale on-disk script fails at `git rev-parse --show-toplevel` before reaching any guarded code. This is why Part A (syncing stale files) is essential, not optional.

## Context

### Affected Files

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- primary fix target (guard cleanup_merged epilogue, create_* functions, add IS_BARE global, add BASH_SOURCE guard, add comment block)
- `AGENTS.md` -- session-start instruction (already fixed in git HEAD, stale on disk -- Part A syncs it)
- `CLAUDE.md` -- references AGENTS.md (already correct)

### Other Scripts Using `git rev-parse --show-toplevel` (Not In Scope But Noted)

These 11 scripts use `|| pwd` or `|| "."` fallbacks, so they don't crash in bare repo context but may resolve to incorrect paths:

- `plugins/soleur/hooks/welcome-hook.sh`
- `plugins/soleur/hooks/stop-hook.sh`
- `plugins/soleur/scripts/setup-ralph-loop.sh`
- `plugins/soleur/skills/community/scripts/discord-setup.sh` (2 locations)
- `plugins/soleur/skills/community/scripts/x-setup.sh` (2 locations)
- `plugins/soleur/skills/community/scripts/bsky-setup.sh` (2 locations)
- `scripts/generate-article-30-register.sh`

These should be tracked as a separate issue for systematic bare-repo hardening across all shell scripts.

### Related Learnings

- `knowledge-base/project/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md` -- documents the original problem
- `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md` -- catch-all dispatchers, parameter validation at init
- `knowledge-base/project/learnings/2026-03-13-archive-kb-stale-path-resolution.md` -- silent failures worse than loud failures
- `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md` -- BASH_SOURCE guard for testability

### Related Commits

- `dc60e90` -- fix: handle bare repos in worktree-manager.sh GIT_ROOT detection (#607)
- `2b31504` -- fix: update archive-kb.sh and worktree-manager.sh to search current KB paths (#600) (#602)

## MVP

### plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh

**1. Add `IS_BARE` global after GIT_ROOT detection (after line 30):**

```bash
# Bare repo flag -- computed once, reused across functions
IS_BARE=false
[[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && IS_BARE=true
```

**2. Guard the "update main checkout" section in `cleanup_merged_worktrees` (replace lines 509-526):**

```bash
# After cleanup, update main checkout so next worktree branches from latest
# Skip entirely for bare repos -- there is no working tree to update
if [[ "$IS_BARE" == "true" ]]; then
  [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Bare repo -- skipping main checkout update (no working tree)${NC}"
else
  # Only check tracked file changes (staged + unstaged) -- untracked files cannot
  # conflict with a fast-forward pull and should not block the update
  if ! git -C "$GIT_ROOT" diff --quiet HEAD 2>/dev/null || ! git -C "$GIT_ROOT" diff --cached --quiet 2>/dev/null; then
    echo -e "${YELLOW}Warning: Main checkout has uncommitted changes to tracked files -- skipping pull${NC}"
  else
    local current_branch
    current_branch=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current_branch" != "main" && "$current_branch" != "master" ]]; then
      git -C "$GIT_ROOT" checkout main 2>/dev/null || git -C "$GIT_ROOT" checkout master 2>/dev/null || true
    fi
    local pull_output
    if pull_output=$(git -C "$GIT_ROOT" pull --ff-only origin main 2>&1); then
      echo -e "${GREEN}Updated main to latest${NC}"
    else
      echo -e "${YELLOW}Warning: Could not pull latest main: $pull_output${NC}"
    fi
  fi
fi
```

**3. Guard `create_worktree` and `create_for_feature` (add at function start):**

```bash
# In create_worktree(), after local branch_name="$1":
if [[ "$IS_BARE" == "true" ]]; then
  echo -e "${RED}Error: Cannot create worktrees from bare repo root. Run from a worktree or non-bare checkout.${NC}"
  exit 1
fi

# Same guard in create_for_feature(), after local name="$1":
if [[ "$IS_BARE" == "true" ]]; then
  echo -e "${RED}Error: Cannot create worktrees from bare repo root. Run from a worktree or non-bare checkout.${NC}"
  exit 1
fi
```

**4. Add BASH_SOURCE guard at script end (replace line 675):**

```bash
# Guard for testability: only run main() when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "${args[@]+"${args[@]}"}"
fi
```

**5. Add explanatory comment at script top (after line 5):**

```bash
# BARE REPO NOTE: This repo uses core.bare=true. On-disk files at the bare root
# are never updated by git -- they become stale after every merge. The IS_BARE
# flag (computed at init) guards all working-tree-dependent operations. If this
# script crashes with "must be run in a work tree", the on-disk copy is stale.
# Run from a worktree instead, or sync with: git show HEAD:<path> > <path>
```

## References

- Related commit: dc60e90 (handle bare repos in worktree-manager.sh GIT_ROOT detection)
- Related PR: #607
- Learning: `knowledge-base/project/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-archive-kb-stale-path-resolution.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md`
