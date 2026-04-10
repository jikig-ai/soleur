---
title: "fix: worktree-manager create reports success but worktree not persisted"
type: fix
date: 2026-04-10
deepened: 2026-04-10
---

# fix: worktree-manager create reports success but worktree not persisted

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 4
**Research sources:** git internals analysis, existing learnings, bare repo behavior analysis

### Key Improvements

1. Use targeted `git worktree repair "$worktree_path"` instead of global repair for better performance and safety
2. Extract shared verification logic into a reusable `verify_worktree_registration()` function to eliminate code duplication
3. Identified that `ensure_bare_config` modifying shared config is unlikely to corrupt worktree *registration* (stored in `.git/worktrees/<name>/`) but can break worktree *functionality* -- reordering still correct but for different reason

### New Considerations Discovered

- `git worktree list --porcelain` output uses absolute paths, so `$worktree_path` must also be absolute for `grep -qF` to match -- already the case since `WORKTREE_DIR` is derived from `GIT_ROOT` which uses `rev-parse --absolute-git-dir`
- The `ensure_bare_config` function modifies `.git/config` (shared config), not `.git/worktrees/<name>/` (registration files) -- so the corruption mechanism is more subtle: git commands run inside the worktree (like the `rev-parse` verification) read the shared config, and if `core.bare=true` is still present (before `ensure_bare_config` fixes it), `rev-parse --show-toplevel` may behave incorrectly inside the new worktree
- `git worktree repair` accepts specific path arguments (`git worktree repair <path>`) which is more targeted than a global repair

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

### Research Insights

**Git worktree registration internals:**

Git worktree registration involves two linked artifacts:

1. A directory at `.git/worktrees/<name>/` containing metadata files (`HEAD`, `gitdir`, `commondir`, `index`, etc.)
2. A `.git` file in the worktree directory pointing back: `gitdir: /path/to/.git/worktrees/<name>`

The `ensure_bare_config` function modifies `.git/config` (the shared config file), NOT the `.git/worktrees/<name>/` registration files. So direct file-level corruption of the registration is unlikely. However, the reordering is still correct for a different reason:

- After `git worktree add` on a bare repo, `core.bare` may still be set to a value in the shared config that makes git commands inside the new worktree behave incorrectly
- The `rev-parse --show-toplevel` verification runs inside the worktree context (`git -C "$worktree_path"`), and if the shared config has `core.bare=true` at that moment (before `ensure_bare_config` removes it), `rev-parse` could return incorrect results
- By running verification FIRST (while `core.bare` may still be wrong in shared config) and THEN fixing the config, we get the most honest verification -- if the worktree works despite the corrupted shared config, it will definitely work after the fix

**Relevant learnings from knowledge base:**

- `pre-merge-hook-bare-repo-diff-false-positive` (2026-04-02): Documents how `git rev-parse --is-inside-work-tree` and `git diff` behave differently in bare repos vs worktrees. Confirms that git commands in bare repo contexts return unexpected results and worktree-specific guards are essential.
- `worktree-manager-post-creation-verification` (2026-04-10): The learning that introduced the current `rev-parse` verification. Confirms `git worktree add` on bare repos can silently fail.
- `lefthook-hangs-in-git-worktrees` (2026-04-02): Documents lefthook/worktree interaction bugs related to `.git` file pointing to `.git/worktrees/<name>`. Confirms git tooling has known issues with worktree contexts in bare repos.

**Edge case -- path matching:**

`git worktree list --porcelain` outputs absolute paths in the format `worktree /absolute/path`. Since `$worktree_path` is derived from `$WORKTREE_DIR/$branch_name` where `$WORKTREE_DIR = $GIT_ROOT/.worktrees` and `$GIT_ROOT` comes from `rev-parse --absolute-git-dir` or `rev-parse --show-toplevel`, the path is already absolute. The `grep -qF` match will work correctly.

However, there is a subtle edge case: if the worktree path contains characters that are special to `grep -F` (unlikely but possible with branch names containing backslashes on some systems), the match could fail. Using exact line matching (`grep -xF "worktree $worktree_path"`) would be more precise but also more fragile if the format changes. The current `grep -qF` approach with the `worktree` prefix is the right balance.

## Proposed Solution

Four changes to `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`:

### 1. Extract shared verification into a function

Both `create_worktree()` and `create_for_feature()` need identical verification logic.
Extract it into a `verify_worktree_created()` function to eliminate duplication and
ensure both paths stay in sync. This directly addresses acceptance criterion "Both
functions follow identical verification flow (no divergence)."

```bash
# worktree-manager.sh — new function, placed after ensure_bare_config()

# Verify a worktree was properly created and registered.
# Checks: (1) rev-parse --show-toplevel matches expected path,
#          (2) worktree appears in git worktree list.
# On registration failure, attempts git worktree repair before giving up.
# Usage: verify_worktree_created "$worktree_path" "$branch_name" "$from_branch"
verify_worktree_created() {
  local worktree_path="$1"
  local branch_name="$2"
  local from_branch="$3"

  # Check 1: Verify the directory is a valid git worktree
  local actual_toplevel
  if ! actual_toplevel=$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null); then
    echo -e "${RED}Error: Worktree creation failed — $worktree_path is not a valid git worktree${NC}"
    echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi
  if [[ "$actual_toplevel" != "$worktree_path" ]]; then
    echo -e "${RED}Error: Worktree path mismatch — expected $worktree_path, got $actual_toplevel${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi

  # Check 2: Verify worktree is registered in git's worktree list (#1932)
  if ! git worktree list --porcelain | grep -qF "worktree $worktree_path"; then
    echo -e "${YELLOW}Warning: Worktree not in git worktree list — attempting repair...${NC}"
    git worktree repair "$worktree_path" 2>/dev/null || true
    if ! git worktree list --porcelain | grep -qF "worktree $worktree_path"; then
      echo -e "${RED}Error: Worktree directory exists but is not registered after repair${NC}"
      git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
      exit 1
    fi
    echo -e "${GREEN}Repair successful — worktree now registered${NC}"
  fi
}
```

### 2. Update `create_worktree()` to use the shared function

Replace the inline verification block and reorder `ensure_bare_config`:

```bash
# create_worktree() — after git worktree add

  echo -e "${BLUE}Creating worktree...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$from_branch"

  # Verify BEFORE fixing config — most honest check of worktree health
  verify_worktree_created "$worktree_path" "$branch_name" "$from_branch"

  # git worktree add on bare repos writes core.bare=false to shared config — fix it
  ensure_bare_config

  # Copy environment files
  copy_env_files "$worktree_path"
```

### 3. Update `create_for_feature()` to use the shared function

Same pattern:

```bash
# create_for_feature() — after git worktree add

  echo -e "${BLUE}Creating worktree...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$from_branch"

  # Verify BEFORE fixing config — most honest check of worktree health
  verify_worktree_created "$worktree_path" "$branch_name" "$from_branch"

  # git worktree add on bare repos writes core.bare=false to shared config — fix it
  ensure_bare_config
```

### 4. Use targeted `git worktree repair` with path argument

Instead of `git worktree repair` (repairs all worktrees), use
`git worktree repair "$worktree_path"` to only repair the specific worktree that
failed registration. This is faster (skips scanning all worktrees) and safer (doesn't
modify other worktrees' state). Available in git 2.17+ (project uses 2.51.0).

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Add `verify_worktree_created()` function; update `create_worktree()` and `create_for_feature()` to use it; reorder `ensure_bare_config` to run after verification |

## Acceptance Criteria

- [ ] `create_worktree()` verifies worktree appears in `git worktree list --porcelain` after creation
- [ ] `create_for_feature()` verifies worktree appears in `git worktree list --porcelain` after creation
- [ ] Verification failure triggers `git worktree repair "$worktree_path"` (targeted) retry before hard error
- [ ] `ensure_bare_config` runs AFTER verification (not between `git worktree add` and verification)
- [ ] Script exits non-zero with clear error message when worktree creation truly fails
- [ ] Existing rev-parse verification remains as first-pass check (inside `verify_worktree_created`)
- [ ] Both functions use the same `verify_worktree_created()` function (no divergence)
- [ ] No behavioral change for the happy path (worktree creation succeeds as before)

## Test Scenarios

- Given a bare repo, when `worktree-manager.sh --yes create test-branch` succeeds,
  then `git worktree list` includes the new worktree path
- Given a bare repo, when `git worktree add` creates a directory but doesn't register
  the worktree, then the script exits non-zero with "not registered" error
- Given a bare repo, when `git worktree repair "$worktree_path"` recovers a missing
  registration, then the script prints "Repair successful" and continues
- Given `ensure_bare_config` would have modified shared config before verification
  (old ordering), then the new ordering delays config modification until after both
  verification checks pass
- Given `worktree-manager.sh --yes feature test-feature` succeeds, then `git worktree
  list` includes the new worktree path AND the spec directory is created

### Research Insights on Testing

**Limitation:** The core failure mode (worktree created but not registered) is
non-deterministic and likely related to I/O timing or git internal state on bare repos.
It cannot be reliably reproduced in a test. The verification logic itself can be tested
by:

1. **Happy path:** Create a worktree normally and verify both checks pass
2. **Manual corruption:** Create a worktree, then manually remove its `.git/worktrees/<name>/gitdir` file, and verify the `git worktree list` check catches it
3. **Repair path:** After manual corruption, verify `git worktree repair` restores the registration

**ShellCheck:** Run `shellcheck worktree-manager.sh` to catch shell scripting issues.
The script already uses `set -euo pipefail` which is good practice.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Only add `git worktree list` check (no reorder) | Minimal change | Doesn't fix root cause (ensure_bare_config still runs between add and verify) | Rejected |
| Remove `ensure_bare_config` after `git worktree add` entirely | Eliminates root cause | Config corruption from `git worktree add` on bare repos would persist, breaking subsequent git operations | Rejected |
| Add sleep between `git worktree add` and verification | Simple | Fragile, cargo-cult timing, doesn't address the real sequencing issue | Rejected |
| Inline verification in both functions (current plan before deepening) | Works | Code duplication between `create_worktree` and `create_for_feature` risks divergence | Rejected |
| Extract `verify_worktree_created()` + reorder + targeted repair (chosen) | Fixes root cause, eliminates duplication, uses targeted repair, defense-in-depth | One new function | **Accepted** |

## Implementation Notes

**Function placement:** Place `verify_worktree_created()` after `ensure_bare_config()` (around line 125) since it logically follows the other utility functions and is called by both `create_worktree()` and `create_for_feature()`.

**`set -euo pipefail` interaction:** The script uses `set -euo pipefail`. The `grep -qF` inside `verify_worktree_created` is inside an `if` statement, so a non-match (exit 1) won't trigger `set -e`. The `2>/dev/null || true` on `git worktree repair` prevents `set -e` from triggering on repair failure.

**Backward compatibility:** The `ensure_bare_config` call at the TOP of `create_worktree()` and `create_for_feature()` (line 265 / line 353) remains unchanged -- it runs before `git worktree add` to fix pre-existing config corruption. Only the SECOND call (after `git worktree add`) is reordered.

## References

- Issue: #1932
- Related PR: #1806 (added rev-parse verification)
- Learning: `knowledge-base/project/learnings/2026-04-10-worktree-manager-post-creation-verification.md`
- Learning: `knowledge-base/project/learnings/workflow-issues/pre-merge-hook-bare-repo-diff-false-positive-20260402.md` (bare repo git command behavior)
- Learning: `knowledge-base/project/learnings/workflow-issues/2026-04-02-lefthook-hangs-in-git-worktrees.md` (worktree/bare repo interaction bugs)
- Related issue: #1756 (original report of worktree creation failure)
- Git documentation: `git worktree repair [<path>...]` repairs corrupted worktree administrative files (git 2.17+)
