---
title: "fix: worktree-manager.sh origin/main fallback doesn't set correct base commit"
type: fix
date: 2026-04-13
---

## Enhancement Summary

**Deepened on:** 2026-04-13
**Sections enhanced:** 3 (Proposed Solution, Test Scenarios, Context)
**Research sources:** git-scm docs, codebase learnings, git update-ref edge case analysis

### Key Improvements

1. Added `git update-ref` safety analysis confirming atomicity and correctness
2. Added edge case for failed fetch (both paths fail) -- no update-ref attempted
3. Confirmed `cleanup_merged_worktrees()` needs identical fix for consistency
4. Added verification step to test scenarios

### New Considerations Discovered

- `git update-ref` uses lockfiles internally -- safe for parallel sessions
- The `elif` guard guarantees `origin/$branch` exists before `update-ref` runs
- No `--no-deref` flag needed -- `refs/heads/main` is always a direct ref

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

### Changes to `cleanup_merged_worktrees()`

Apply the same fix to the fallback at lines 820-824:

```bash
# Current (broken):
if git fetch origin main:main 2>/dev/null; then
  echo -e "${GREEN}Updated main to latest${NC}"
elif git fetch origin main 2>/dev/null; then
  # Fallback: non-fast-forward (e.g., force-push) -- at least update origin/main
  echo -e "${YELLOW}Warning: Could not fast-forward local main -- fetched origin/main only${NC}"
fi

# Fixed:
if git fetch origin main:main 2>/dev/null; then
  echo -e "${GREEN}Updated main to latest${NC}"
elif git fetch origin main 2>/dev/null; then
  # Fast-forward failed but fetch succeeded -- force-update local ref to match remote.
  # Safe because direct commits to main are prohibited (hook-enforced).
  git update-ref refs/heads/main origin/main
  echo -e "${YELLOW}Warning: Could not fast-forward local main -- force-updated to origin/main${NC}"
fi
```

### Research Insights

**Safety of `git update-ref` in this context:**

- `git update-ref` is atomic -- it uses a lockfile (`refs/heads/main.lock`)
  internally, so parallel sessions cannot corrupt the ref
- The `elif` guard guarantees `origin/$branch` exists before `update-ref` runs
  (the fetch that populated it succeeded)
- No `--no-deref` flag is needed because `refs/heads/main` is always a direct
  ref (not a symbolic ref like HEAD)
- `git update-ref` does NOT verify ancestry -- it unconditionally moves the ref.
  This is intentional here: direct commits to main are prohibited, so local main
  should always be an ancestor of (or equal to) origin/main. If it somehow isn't,
  force-updating is the correct recovery

**Edge case: both fetch paths fail:**

If `git fetch origin "$branch:$branch"` AND `git fetch origin "$branch"` both
fail (network down, remote unreachable), neither branch executes and
`update_branch_ref` returns silently. The worktree will be created from whatever
local main currently points to. This is acceptable -- network failure is
unrecoverable and the existing behavior is preserved

**References:**

- [git-update-ref documentation](https://git-scm.com/docs/git-update-ref)
- [git update-ref best practices](https://copyprogramming.com/howto/git-update-ref-appears-to-do-nothing)

### File

`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

## Acceptance Criteria

- [x] When `git fetch origin main:main` fails (non-fast-forward), `update_branch_ref`
  force-updates the local `main` ref to `origin/main` via `git update-ref`
- [x] Worktrees created after a failed fast-forward are based on `origin/main`,
  not the stale local `main`
- [x] The warning message is updated to say "force-updated" instead of just "using"
- [x] The same fix applies to both `create_worktree()` and `create_for_feature()` paths
  (both call `update_branch_ref`, so fixing the function fixes both)
- [x] The `cleanup_merged_worktrees()` fallback path (lines 820-824) receives the same
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
- Given a bare repo where both fetch paths fail (network down), when
  `update_branch_ref` completes, then no `update-ref` is attempted and the function
  returns silently (existing behavior preserved)
- Given `cleanup_merged_worktrees()` runs in a bare repo where `git fetch origin
  main:main` fails, when the cleanup completes, then `git rev-parse main` should
  equal `git rev-parse origin/main` (same fix applied to cleanup path)

### Verification commands

After applying the fix, verify in a bare repo where local main is stale:

```bash
# Record stale state
git rev-parse main          # Should show old commit
git rev-parse origin/main   # Should show newer commit

# Run worktree creation
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create test-branch

# Verify fix
git rev-parse main          # Should now equal origin/main
git -C .worktrees/test-branch log --oneline -1  # Should show latest commit

# Cleanup
git worktree remove .worktrees/test-branch
git branch -D test-branch
```

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
