---
title: "fix: worktree-manager.sh origin/main fallback doesn't set correct base commit"
type: fix
date: 2026-04-13
---

# fix: worktree-manager.sh origin/main fallback sets correct base commit

## Overview

When `worktree-manager.sh create` cannot fast-forward local main, it warns "Could
not fast-forward local main -- using origin/main" but the worktree is still created
from the stale local `main` ref. This causes worktrees to miss recently merged PRs.

## Problem Statement

The `update_branch_ref()` function has a fallback path that is misleading and
incomplete. When `git fetch origin main:main` fails (non-fast-forward), it falls
back to `git fetch origin main`, which only updates `origin/main` and `FETCH_HEAD`
-- the local `main` ref stays stale. The warning message says "using origin/main"
but the subsequent `git worktree add -b <branch> <path> main` still uses the
stale local `main`.

**Observed in:** Session fixing #2046/#2047/#2048 -- worktree was at `613169a5`
(old main) instead of `932a7a1c` (origin/main with PR #2036 merged). Required
manual `git rebase origin/main`.

**Root cause trace:**

1. `update_branch_ref("main")` runs `git fetch origin main:main` (line 188)
2. Fast-forward fails (e.g., local main diverged due to a prior update-ref or
   interrupted fetch)
3. Falls back to `git fetch origin main` (line 190) -- updates `origin/main` only
4. Returns without updating local `main`
5. `create_worktree()` runs `git worktree add -b <branch> <path> main` (line 364)
6. `main` still points to the stale commit

The same pattern exists in `create_for_feature()` (line 424).

## Proposed Solution

When `git fetch origin main:main` fails, force-update the local `main` ref to
match `origin/main` using `git update-ref`. This is safe because:

- Direct commits to main are prohibited (hook-enforced)
- The only valid state for local `main` is tracking `origin/main`
- The warning already says "using origin/main" -- the behavior should match

### Changes to `update_branch_ref()`

In the bare repo fallback branch (lines 188-192 of `worktree-manager.sh`):

```bash
# Current (broken):
if git fetch origin "$branch:$branch" 2>/dev/null; then
  echo -e "${GREEN}Updated $branch to latest (via fetch)${NC}"
elif git fetch origin "$branch" 2>/dev/null; then
  echo -e "${YELLOW}Warning: Could not fast-forward local $branch -- using origin/$branch${NC}"
fi

# Fixed:
if git fetch origin "$branch:$branch" 2>/dev/null; then
  echo -e "${GREEN}Updated $branch to latest (via fetch)${NC}"
elif git fetch origin "$branch" 2>/dev/null; then
  # Fast-forward failed but fetch succeeded -- force-update local ref to match remote.
  # Safe because direct commits to main are prohibited (hook-enforced).
  git update-ref "refs/heads/$branch" "origin/$branch"
  echo -e "${YELLOW}Warning: Could not fast-forward local $branch -- force-updated to origin/$branch${NC}"
fi
```

### File

`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

## Acceptance Criteria

- [ ] When `git fetch origin main:main` fails (non-fast-forward), `update_branch_ref`
  force-updates the local `main` ref to `origin/main` via `git update-ref`
- [ ] Worktrees created after a failed fast-forward are based on `origin/main`,
  not the stale local `main`
- [ ] The warning message is updated to say "force-updated" instead of just "using"
- [ ] The same fix applies to both `create_worktree()` and `create_for_feature()` paths
  (both call `update_branch_ref`, so fixing the function fixes both)
- [ ] The `cleanup_merged_worktrees()` fallback path (lines 820-824) receives the same
  fix for consistency

## Test Scenarios

- Given a bare repo where local `main` is behind `origin/main` (non-fast-forwardable),
  when `worktree-manager.sh create <name>` runs, then the new worktree should contain
  files from the latest `origin/main` commit
- Given a bare repo where `git fetch origin main:main` fails, when `update_branch_ref`
  completes, then `git rev-parse main` should equal `git rev-parse origin/main`
- Given a bare repo where local `main` is already at `origin/main`, when
  `worktree-manager.sh create <name>` runs, then the fast-forward path succeeds and
  no force-update is needed

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

### Related Learnings

- `2026-04-12-stale-main-ref-breaks-multi-issue-worktree-creation.md` -- Documents
  the exact symptom. Workaround was manual `git update-ref refs/heads/main origin/main`.
  This plan makes the workaround automatic.
- `2026-03-18-bare-repo-cleanup-stale-script-and-fetch-refspec.md` -- Documents why
  `git fetch origin main` != `git fetch origin main:main`. The refspec form was added
  to `cleanup_merged_worktrees` but the `update_branch_ref` fallback was not fixed.

### Related Issues

- Ref #2078

## References

- File: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- `update_branch_ref()`: lines 180-197
- `create_worktree()`: lines 310-383
- `create_for_feature()`: lines 386-452
- `cleanup_merged_worktrees()`: lines 679-863 (fallback at lines 820-824)
