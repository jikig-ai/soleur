---
title: "feat: Pull latest main after PR merge and worktree cleanup"
type: feat
date: 2026-02-24
version_bump: PATCH
deepened: 2026-02-24
---

# feat: Pull latest main after PR merge and worktree cleanup

After merging a PR and running `cleanup-merged`, the main checkout stays at whatever commit it was before the merge. The next worktree creation (`git worktree add ... main`) branches from a stale main, requiring an immediate `git fetch origin main && git merge origin/main` in the new worktree. This is a gap in the post-merge lifecycle.

## Enhancement Summary

**Deepened on:** 2026-02-24
**Sections enhanced:** 3 (Edge cases, MVP code, References)

### Key Improvements
1. Added `git pull --ff-only` instead of `git pull` to prevent accidental merge commits in the main checkout
2. Added edge case for detached HEAD state (can happen if a previous operation left the main checkout detached)
3. Added edge case for the session-start hygiene caller (runs from repo root, so no cd needed)

### New Considerations Discovered
- Using `git pull --ff-only` is safer than `git pull` -- main should always fast-forward since no one commits directly to main. If `--ff-only` fails, it signals a diverged state that needs investigation, not silent merging.
- The `git fetch --prune` that already runs at the top of `cleanup_merged_worktrees` means the remote refs are already up to date. The pull only needs to advance the local branch pointer -- a fast-forward is always sufficient.

## Non-goals

- Changing the cleanup-merged detection logic (it already works correctly)
- Adding a new skill or command (this is a small addition to existing flows)
- Modifying session-start hygiene (that already runs cleanup-merged; adding pull there too is considered but out of scope for now)

## Proposed Solution

Add `git checkout main && git pull --ff-only origin main` after `cleanup-merged` completes in three locations:

1. **`worktree-manager.sh` `cleanup_merged_worktrees` function** -- After cleaning worktrees and branches, if any were cleaned, checkout main and pull. This is the single source of truth for post-merge cleanup.
2. **`ship/SKILL.md` Phase 8** -- Add a step after `cleanup-merged` that instructs the agent to verify main is up to date.
3. **`merge-pr/SKILL.md` Phase 7** -- Same addition after cleanup.
4. **`AGENTS.md` Workflow Completion Protocol step 10** -- Add pull-latest instruction after cleanup-merged.

### Why the script is the right primary location

The `cleanup_merged_worktrees` function already runs `git fetch --prune`. It knows when branches were cleaned. Adding the pull there means every caller (ship, merge-pr, session-start hygiene) gets the behavior automatically. The skill instructions serve as documentation reinforcement.

### Research Insights

**From institutional learnings:**

- **Ship integration pattern** (`2026-02-12-ship-integration-pattern-for-post-merge-steps.md`): Post-merge steps should be thin conditional checks in the existing flow. The script is the right place; skill instructions are reinforcement only. This pattern is confirmed.
- **Stale worktrees learning** (`2026-02-21-stale-worktrees-accumulate-across-sessions.md`): Session boundaries are the most common failure point. Adding the pull to the script (not just skill instructions) means every trigger path -- including session-start hygiene -- gets the behavior. This avoids the "last step in session gets skipped" failure mode.
- **Path mismatch learning** (`2026-02-22-cleanup-merged-path-mismatch.md`): The script already uses `git worktree list --porcelain` for path resolution. The pull-latest code uses `git -C "$GIT_ROOT"` which correctly references the repo root without path construction from branch names.

**Best practice -- fast-forward only:**

Since AGENTS.md prohibits committing directly to main, the local main branch should always be a strict ancestor of `origin/main`. Using `git pull --ff-only` enforces this invariant. If it fails, the main checkout has diverged -- which is a configuration error that should surface as a warning, not be silently resolved with a merge commit.

### Edge cases

- **Multiple worktrees active:** If other worktrees exist, `git checkout main` in the main repo root is safe -- worktrees are independent checkouts. The main repo checkout is typically on main already.
- **Main checkout has uncommitted changes:** The script should check `git status --porcelain` before switching. If dirty, warn and skip the pull (same defensive pattern as the existing uncommitted-changes check for worktrees).
- **Network failure on pull:** Use `|| true` like the existing `git pull origin "$from_branch" || true` pattern in the script's `create_worktree` function.
- **No branches cleaned:** If `cleanup_merged_worktrees` found nothing to clean, skip the pull (main is already current from the fetch).
- **Detached HEAD in main checkout:** If `git rev-parse --abbrev-ref HEAD` returns `HEAD` (detached), the script should checkout main first. The existing fallback chain (`checkout main || checkout master || true`) handles this.
- **Session-start hygiene context:** When `cleanup-merged` runs from session-start hygiene, the user is already at the repo root. The `git -C "$GIT_ROOT"` approach works regardless of the caller's cwd.

## Acceptance Criteria

- [x] After `cleanup-merged` cleans at least one branch, the main checkout is on the `main` branch at the latest remote commit
- [x] If no branches were cleaned, no checkout or pull happens
- [x] If the main checkout has uncommitted changes, warn and skip the pull
- [x] Network failure on pull degrades gracefully (warn, do not abort)
- [x] Ship Phase 8 instructions include pull-latest after cleanup
- [x] Merge-pr Phase 7 instructions include pull-latest after cleanup
- [x] AGENTS.md step 10 mentions pulling latest after cleanup

## Test Scenarios

- Given a merged PR and `cleanup-merged` cleans 1 worktree, when the function completes, then main checkout is at the latest origin/main commit
- Given a merged PR but `cleanup-merged` finds no gone branches, when the function completes, then no checkout or pull is attempted
- Given `cleanup-merged` cleans a worktree but main checkout has uncommitted changes, when the function completes, then a warning is printed and pull is skipped
- Given `cleanup-merged` cleans a worktree but network is down, when `git pull` fails, then a warning is printed and the script exits 0
- Given `cleanup-merged` cleans a worktree and main checkout is in detached HEAD state, when the function completes, then main is checked out and pulled

## MVP

### `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

Add to the end of `cleanup_merged_worktrees()`, after the summary output block:

```bash
# After cleanup, update main checkout so next worktree branches from latest
if [[ ${#cleaned[@]} -gt 0 ]]; then
  # Only pull if main checkout is clean
  local main_status
  main_status=$(git -C "$GIT_ROOT" status --porcelain 2>/dev/null)
  if [[ -n "$main_status" ]]; then
    [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Main checkout has uncommitted changes -- skipping pull${NC}"
  else
    local current_branch
    current_branch=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current_branch" != "main" && "$current_branch" != "master" ]]; then
      git -C "$GIT_ROOT" checkout main 2>/dev/null || git -C "$GIT_ROOT" checkout master 2>/dev/null || true
    fi
    if ! git -C "$GIT_ROOT" pull --ff-only origin main 2>/dev/null; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not pull latest main${NC}"
    else
      [[ "$verbose" == "true" ]] && echo -e "${GREEN}Updated main to latest${NC}"
    fi
  fi
fi
```

**Implementation notes:**
- Uses `git -C "$GIT_ROOT"` to ensure operations target the main checkout regardless of cwd
- Uses `--ff-only` because main should never diverge from origin/main (no direct commits to main)
- Respects the existing `verbose` pattern -- silent in non-TTY (CI, piped output), verbose in interactive mode
- All variables declared with `local` per shell script constitution rules
- Error suppression via `2>/dev/null` matches existing patterns in the function

### `plugins/soleur/skills/ship/SKILL.md` (Phase 8)

After the cleanup-merged instruction (line ~359), add a numbered step:

```text
3. After cleanup, verify main is up to date. The `cleanup-merged` script now
   automatically pulls latest main when it cleans branches. Verify by running
   `git log --oneline -1` from the repo root -- the HEAD commit should match
   the merge commit from the PR.
```

### `plugins/soleur/skills/merge-pr/SKILL.md` (Phase 7.3)

After the cleanup step in the end-of-run report section, add:

```text
The `cleanup-merged` script automatically pulls latest main after cleaning
branches. The end-of-run report should confirm the main checkout is current.
```

### `AGENTS.md` (Workflow Completion Protocol step 10)

Update step 10 to mention that cleanup-merged now pulls latest main. Change:

```text
10. **Merge and cleanup** -- After CI passes, merge with `gh pr merge <number> --squash`.
Then immediately run `worktree-manager.sh cleanup-merged` from the repo root.
```

To:

```text
10. **Merge and cleanup** -- After CI passes, merge with `gh pr merge <number> --squash`.
Then immediately run `worktree-manager.sh cleanup-merged` from the repo root. The script
automatically pulls latest main after cleaning branches, so the next worktree will branch
from the current state.
```

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Add pull-latest block to `cleanup_merged_worktrees()` |
| `plugins/soleur/skills/ship/SKILL.md` | Add verification step in Phase 8 |
| `plugins/soleur/skills/merge-pr/SKILL.md` | Add note about auto-pull in Phase 7.3 |
| `AGENTS.md` | Update Workflow Completion Protocol step 10 |

## References

- Existing pattern: `worktree-manager.sh` lines 105-106 (`git checkout` + `git pull origin` with `|| true`)
- Learning: `knowledge-base/learnings/2026-02-09-worktree-cleanup-gap-after-merge.md` -- original trigger gap identification
- Learning: `knowledge-base/learnings/2026-02-21-stale-worktrees-accumulate-across-sessions.md` -- session boundary failure mode
- Learning: `knowledge-base/learnings/2026-02-22-cleanup-merged-path-mismatch.md` -- path construction vs porcelain lookup
- Learning: `knowledge-base/learnings/2026-02-12-ship-integration-pattern-for-post-merge-steps.md` -- thin conditional checks pattern
- Ship skill Phase 8: `plugins/soleur/skills/ship/SKILL.md:334-365`
- Merge-pr skill Phase 7: `plugins/soleur/skills/merge-pr/SKILL.md:358-389`
