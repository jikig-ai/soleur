# Brainstorm: Pull Latest Before Worktree Creation

**Date:** 2026-02-06
**Status:** Ready for planning

## What We're Building

Ensure git worktrees are created from the latest remote state by adding `git pull` before branch creation in the `create_for_feature()` function.

Currently, `create_worktree()` already pulls before creating a worktree, but `create_for_feature()` (used by `/soleur:brainstorm`) does not. This inconsistency can result in feature branches being based on stale local refs.

## Why This Approach

- **Consistency:** Match the existing pattern in `create_worktree()` which already does `git checkout $from_branch && git pull origin $from_branch`
- **Simplicity:** Reuse proven pattern rather than inventing a new approach
- **Safety:** The existing pattern uses `|| true` to gracefully handle offline/auth failures

## Key Decisions

1. **Scope:** Fix `create_for_feature()` to match `create_worktree()` behavior
2. **Pattern:** Use `git checkout $from_branch && git pull origin $from_branch || true`
3. **Location:** Add the pull logic before line 159 (before `git worktree add`)

## Implementation Notes

The change is straightforward - add 4 lines to `create_for_feature()`:

```bash
# Update base branch before creating worktree
echo -e "${BLUE}Updating $from_branch...${NC}"
git checkout "$from_branch"
git pull origin "$from_branch" || true
```

## Open Questions

None - requirements are clear.

## Files to Modify

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
