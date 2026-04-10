---
title: "fix: worktree-manager create reports success but worktree not persisted"
type: fix
date: 2026-04-10
---

# fix: worktree-manager create reports success but worktree not persisted

## Overview

`worktree-manager.sh --yes create <name>` can report success (exit 0, print success
message with path) while the created worktree is not registered in `git worktree list`
and the directory is not accessible. PR #1806 added post-creation `rev-parse
--show-toplevel` verification, but this only detects failures where the directory is
completely broken -- it does not catch the case where the directory exists and passes
`rev-parse` but is not registered in the git worktree list.

## Problem Statement

The root cause is a sequencing issue in `create_worktree()` and `create_for_feature()`:

1. `git worktree add` at line 317 creates the worktree
2. `ensure_bare_config` at line 320 immediately modifies the shared `.git/config`
   (removes `core.bare`, removes `core.worktree`, sets `extensions.worktreeConfig`)
3. The verification at lines 322-334 checks `rev-parse --show-toplevel` inside the
   worktree directory

The hypothesis from the prevention strategist analysis: `ensure_bare_config` modifying
the shared git config immediately after `git worktree add` could transiently corrupt
the worktree registration. Git stores worktree metadata in `.git/worktrees/<name>/`,
and the shared config modifications could interfere with this process on slow I/O or
when git hasn't fully flushed its state.

Additionally, the current verification (`rev-parse --show-toplevel`) only checks that
the directory is a valid git working tree -- it does not verify that the worktree is
registered in `git worktree list`. A directory can pass `rev-parse` but fail to appear
in the worktree list, which is the exact failure mode reported in #1932.

## Proposed Solution

Three changes to `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`:

### 1. Add `git worktree list` verification as a final gate

After the existing `rev-parse --show-toplevel` check, add a `git worktree list
--porcelain | grep` assertion that verifies the worktree path appears in the
registered worktree list. This catches the specific failure mode where the directory
exists but the worktree is not registered.

```bash
# worktree-manager.sh — inside create_worktree() and create_for_feature(),
# after the existing rev-parse verification block

# Verify worktree is registered in git's worktree list (catches #1932 failure mode)
if ! git worktree list --porcelain | grep -qF "worktree $worktree_path"; then
  echo -e "${RED}Error: Worktree directory exists but is not registered in git worktree list${NC}"
  echo -e "${YELLOW}Hint: Run 'git worktree repair' then retry${NC}"
  git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
  exit 1
fi
```

### 2. Add retry logic on verification failure

When the `git worktree list` verification fails, attempt one retry with `git worktree
repair` before giving up. This handles transient registration corruption that
`ensure_bare_config` may cause.

```bash
# worktree-manager.sh — inside create_worktree() and create_for_feature(),
# replacing the simple git worktree list check above

# Verify worktree is registered in git's worktree list (catches #1932 failure mode)
if ! git worktree list --porcelain | grep -qF "worktree $worktree_path"; then
  echo -e "${YELLOW}Warning: Worktree not in git worktree list — attempting repair...${NC}"
  git worktree repair 2>/dev/null || true
  if ! git worktree list --porcelain | grep -qF "worktree $worktree_path"; then
    echo -e "${RED}Error: Worktree directory exists but is not registered after repair${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi
  echo -e "${GREEN}Repair successful — worktree now registered${NC}"
fi
```

### 3. Move `ensure_bare_config` after verification in both functions

Reorder the post-creation steps so that verification happens immediately after
`git worktree add`, before `ensure_bare_config` has a chance to modify the shared
config. The config fix is still needed (git worktree add on bare repos corrupts the
shared config), but it should run after we've confirmed the worktree is properly
registered.

Current order (lines 317-334):
```
git worktree add        # line 317
ensure_bare_config      # line 320 — modifies shared config
rev-parse verification  # lines 322-334
```

New order:
```
git worktree add        # creates worktree
rev-parse verification  # verify directory is valid
worktree list check     # verify registration (with retry+repair)
ensure_bare_config      # fix shared config AFTER verification
```

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Reorder `ensure_bare_config`, add `git worktree list` verification with retry, in both `create_worktree()` and `create_for_feature()` |

## Acceptance Criteria

- [ ] `create_worktree()` verifies worktree appears in `git worktree list --porcelain` after creation
- [ ] `create_for_feature()` verifies worktree appears in `git worktree list --porcelain` after creation
- [ ] Verification failure triggers `git worktree repair` retry before hard error
- [ ] `ensure_bare_config` runs AFTER verification (not between `git worktree add` and verification)
- [ ] Script exits non-zero with clear error message when worktree creation truly fails
- [ ] Existing rev-parse verification remains as first-pass check
- [ ] Both functions follow identical verification flow (no divergence)

## Test Scenarios

- Given a bare repo, when `worktree-manager.sh --yes create test-branch` succeeds,
  then `git worktree list` includes the new worktree path
- Given a bare repo, when `git worktree add` creates a directory but doesn't register
  the worktree, then the script exits non-zero with "not registered" error
- Given a bare repo, when `git worktree repair` recovers a missing registration, then
  the script prints "Repair successful" and continues
- Given `ensure_bare_config` would have modified shared config before verification
  (old ordering), then the new ordering delays config modification until after both
  verification checks pass

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Only add `git worktree list` check (no reorder) | Minimal change | Doesn't fix root cause (ensure_bare_config still runs between add and verify) | Rejected |
| Remove `ensure_bare_config` after `git worktree add` entirely | Eliminates root cause | Config corruption from `git worktree add` on bare repos would persist, breaking subsequent git operations | Rejected |
| Add sleep between `git worktree add` and verification | Simple | Fragile, cargo-cult timing, doesn't address the real sequencing issue | Rejected |
| Reorder + verify + retry (chosen) | Fixes root cause, adds defense-in-depth, handles edge cases | Slightly more code | **Accepted** |

## References

- Issue: #1932
- Related PR: #1806 (added rev-parse verification)
- Learning: `knowledge-base/project/learnings/2026-04-10-worktree-manager-post-creation-verification.md`
- Related issue: #1756 (original report of worktree creation failure)
