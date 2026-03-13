---
title: "fix: bare repo on-disk files are stale, causing worktree-manager.sh cleanup-merged to fail"
type: fix
date: 2026-03-13
---

# fix: Bare Repo On-Disk Files Are Stale, Causing worktree-manager.sh cleanup-merged to Fail

## Overview

`worktree-manager.sh cleanup-merged` fails with `fatal: this operation must be run in a work tree` when invoked from the bare repo root. The fix from commit dc60e90 is in git HEAD but the on-disk files at the bare repo root are stale -- bare repos (`core.bare=true`) have no working tree, so git never updates on-disk files. Claude Code reads CLAUDE.md/AGENTS.md from disk, not from git, so the session-start instruction in the stale on-disk AGENTS.md still says "from the repo root" and points to the stale on-disk script.

## Problem Statement

### Root Cause

Soleur uses `core.bare=true` to prevent accidental commits to main. All work happens in worktrees. This means:

1. **On-disk files at the bare repo root are frozen** at whatever state they were when `core.bare` was set. Git never updates them because there is no working tree checkout.
2. **Claude Code reads AGENTS.md from disk.** The stale on-disk AGENTS.md (line 28) says: `At session start, from the repo root: run bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.
3. **The stale on-disk worktree-manager.sh** still has `GIT_ROOT=$(git rev-parse --show-toplevel)` (no bare-repo detection), which fails immediately with exit code 128.

### What's Already Fixed in Git HEAD (But Stale on Disk)

- **AGENTS.md** (git HEAD line 29): Updated to say "from any active worktree (not the bare repo root)" with relative path `../../plugins/soleur/...`
- **worktree-manager.sh** (git HEAD lines 20-29): Bare repo detection via `git rev-parse --is-bare-repository`

### Additional Problems in cleanup_merged_worktrees When Run From Bare Repo

Even with the GIT_ROOT fix, the "update main checkout" section (lines 511-525) calls commands that require a working tree:

- `git -C "$GIT_ROOT" diff --quiet HEAD` -- fails in bare repo
- `git -C "$GIT_ROOT" checkout main` -- fails in bare repo
- `git -C "$GIT_ROOT" pull --ff-only origin main` -- fails in bare repo

In a bare repo, there is no "main checkout" to update. These must be guarded.

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

### Part B: Harden worktree-manager.sh for Bare Repo Context

1. **Guard the "update main checkout" section** in `cleanup_merged_worktrees`: Skip the entire `git diff`, `git checkout`, `git pull` block when `core.bare=true`. There is no working tree to update.

2. **Guard other working-tree-dependent operations:** Audit the full script for commands that assume a working tree exists (e.g., `ensure_gitignore`, `create_worktree`'s `git checkout`, etc.). Add early returns or skip-guards when bare.

### Part C: Prevent Future Staleness (Session-Start Resilience)

The AGENTS.md session-start instruction already directs running from a worktree (in git HEAD). But as defense-in-depth:

1. **Add a comment block** at the top of worktree-manager.sh explaining the bare-repo-stale-file problem, so future editors understand why the bare detection exists.
2. **Consider a self-healing approach**: The script could detect it's running a stale version (compare its own content hash against `git show HEAD:...`) and print a warning suggesting the user sync on-disk files. This is optional -- the primary fix is resilience.

## Acceptance Criteria

- [ ] `worktree-manager.sh cleanup-merged` succeeds when invoked from the bare repo root (exit 0, no fatal errors)
- [ ] `worktree-manager.sh cleanup-merged` succeeds when invoked from a worktree (existing behavior preserved)
- [ ] The "update main checkout" section is skipped (with informational message) when `core.bare=true`
- [ ] On-disk files at bare repo root match git HEAD after fix is applied
- [ ] AGENTS.md session-start instruction works regardless of which copy (disk or git) Claude Code reads

## Test Scenarios

- Given `core.bare=true` and stale on-disk files, when `cleanup-merged` runs from bare repo root, then it exits 0 with no fatal errors and cleans up any [gone] branches
- Given `core.bare=true` with no [gone] branches, when `cleanup-merged` runs from bare repo root, then it exits 0 silently (non-TTY) or prints "No merged branches" (TTY)
- Given a worktree context, when `cleanup-merged` runs, then existing behavior is unchanged (branches cleaned, specs archived, main updated)
- Given `core.bare=true`, when `cleanup-merged` finds [gone] branches, then it skips the "update main checkout" block (no `git checkout`, `git pull`) and prints a warning that bare repos cannot auto-update

## Context

### Affected Files

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- primary fix target
- `AGENTS.md` -- session-start instruction (already fixed in git HEAD, stale on disk)
- `CLAUDE.md` -- references AGENTS.md (already correct)

### Related Learnings

- `knowledge-base/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md` -- documents the original problem
- `knowledge-base/learnings/2026-02-22-cleanup-merged-path-mismatch.md` -- prior worktree path issues

### Related Commits

- `dc60e90` -- fix: handle bare repos in worktree-manager.sh GIT_ROOT detection (#607)
- `2b31504` -- fix: update archive-kb.sh and worktree-manager.sh to search current KB paths (#600) (#602)

## MVP

### plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh

Guard the "update main checkout" section to skip when bare:

```bash
# After cleanup, update main checkout so next worktree branches from latest
# Skip entirely for bare repos -- there is no working tree to update
if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Bare repo detected -- skipping main checkout update (no working tree)${NC}"
else
  # Only check tracked file changes ...
  if ! git -C "$GIT_ROOT" diff --quiet HEAD 2>/dev/null || ! git -C "$GIT_ROOT" diff --cached --quiet 2>/dev/null; then
    echo -e "${YELLOW}Warning: Main checkout has uncommitted changes to tracked files -- skipping pull${NC}"
  else
    # ... existing checkout + pull logic ...
  fi
fi
```

## References

- Related commit: dc60e90 (handle bare repos in worktree-manager.sh GIT_ROOT detection)
- Related PR: #607
- Learning: `knowledge-base/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md`
