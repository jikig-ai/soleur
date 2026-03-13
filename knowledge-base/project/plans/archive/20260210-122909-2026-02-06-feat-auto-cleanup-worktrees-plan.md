---
title: "feat: Auto-Cleanup Worktrees After PR Merge"
type: feat
date: 2026-02-06
issue: "#15"
related: "#10"
branch: feat-auto-cleanup-worktrees
---

# feat: Auto-Cleanup Worktrees After PR Merge

## Overview

Extend `worktree-manager.sh` with a `cleanup-merged` command that automatically detects merged branches (via git's `[gone]` marker), removes their worktrees, archives spec directories, and deletes local branches. Triggered via Claude Code hooks on SessionStart and after `gh pr merge`.

## Problem Statement / Motivation

Worktrees persist after PR merge, creating clutter and requiring manual cleanup. Users must remember to run `worktree-manager.sh cleanup` and manually archive spec directories. This automation was identified as a v2 enhancement in the spec workflow learnings.

## Proposed Solution

Add `cleanup-merged` command to the existing `worktree-manager.sh` script with two trigger mechanisms:

1. **SessionStart hook** - Catches PRs merged via GitHub UI while user was away
2. **PostToolUse hook** - Catches PRs merged within the current Claude Code session

Both triggers call the same cleanup logic with `--auto` flag for silent operation.

## Technical Approach

### Detection Flow

```
git fetch --prune
    |
    v
git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | grep '\[gone\]'
    |
    v
For each [gone] branch:
    |
    +---> Skip if active worktree (PWD match)
    |
    +---> Skip if worktree has uncommitted changes (safety check)
    |
    +---> Archive spec: knowledge-base/specs/feat-<name>/ -> archive/YYYY-MM-DD-HHMMSS-feat-<name>/
    |
    +---> Remove worktree: git worktree remove .worktrees/feat-<name>
    |
    +---> Delete branch: git branch -d feat-<name>
    |
    v
Output summary (verbose if TTY, quiet otherwise)
```

### Files to Modify

| File | Changes |
|------|---------|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Add `cleanup-merged` function and command handler |
| `plugins/soleur/.claude-plugin/plugin.json` | Add hooks configuration |

### worktree-manager.sh Changes

Add new function `cleanup_merged_worktrees()` after line 331:

```bash
# worktree-manager.sh:332
cleanup_merged_worktrees() {
  # Determine output mode: verbose if TTY, quiet otherwise
  local verbose=false
  [[ -t 1 ]] && verbose=true

  # Fetch to update remote tracking info
  local fetch_error
  if ! fetch_error=$(git fetch --prune 2>&1); then
    [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not fetch from remote: $fetch_error${NC}"
    return 0
  fi

  # Find branches with [gone] tracking (robust detection)
  local gone_branches
  gone_branches=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads 2>/dev/null | grep '\[gone\]' | cut -d' ' -f1)

  if [[ -z "$gone_branches" ]]; then
    [[ "$verbose" == "true" ]] && echo -e "${GREEN}No merged branches to clean up${NC}"
    return 0
  fi

  local cleaned=()

  for branch in $gone_branches; do
    local worktree_path="$WORKTREE_DIR/$branch"
    local spec_dir="$GIT_ROOT/knowledge-base/specs/$branch"
    local archive_dir="$GIT_ROOT/knowledge-base/specs/archive"

    # Skip if active worktree
    if [[ "$PWD" == "$worktree_path"* ]]; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) $branch - currently active${NC}"
      continue
    fi

    # Skip if worktree has uncommitted changes (safety check)
    if [[ -d "$worktree_path" ]]; then
      local status
      status=$(git -C "$worktree_path" status --porcelain 2>/dev/null)
      if [[ -n "$status" ]]; then
        [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) $branch - has uncommitted changes${NC}"
        continue
      fi
    fi

    # Archive spec directory if exists (timestamp prevents collisions)
    if [[ -d "$spec_dir" ]]; then
      local safe_branch=$(echo "$branch" | tr '/' '-')
      local archive_name="$(date +%Y-%m-%d-%H%M%S)-$safe_branch"
      local archive_path="$archive_dir/$archive_name"

      mkdir -p "$archive_dir"
      if ! mv "$spec_dir" "$archive_path" 2>/dev/null; then
        [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not archive spec for $branch${NC}"
      fi
    fi

    # Remove worktree if exists
    if [[ -d "$worktree_path" ]]; then
      if ! git worktree remove "$worktree_path" 2>/dev/null; then
        [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not remove worktree for $branch${NC}"
        continue
      fi
    fi

    # Delete branch (safe delete - won't delete if has unmerged commits)
    if ! git branch -d "$branch" 2>/dev/null; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not delete branch $branch (may have unmerged commits)${NC}"
    fi

    cleaned+=("$branch")
  done

  # Output summary
  if [[ ${#cleaned[@]} -gt 0 ]]; then
    echo -e "${GREEN}Cleaned ${#cleaned[@]} merged worktree(s): ${cleaned[*]}${NC}"
  fi
}
```

Update main command handler to include new command:

```bash
# worktree-manager.sh:337 (in case statement)
    cleanup-merged)
      cleanup_merged_worktrees
      ;;
```

Update help text:

```bash
# worktree-manager.sh:379 (in show_help)
  cleanup-merged              Clean up worktrees for merged branches
                              (detects [gone] branches, archives specs)
```

### Hook Configuration

**Note:** Claude Code hooks may be configured in `.claude/settings.json` (project) or user settings, not plugin.json. Verify location before implementation.

Add to `.claude/settings.local.json` (or appropriate hooks config):

```json
{
  "hooks": [
    {
      "event": "SessionStart",
      "command": ["./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh", "cleanup-merged"]
    }
  ]
}
```

**Deferred:** PostToolUse hook for `gh pr merge` - add only if SessionStart doesn't provide sufficient coverage. The script uses TTY detection, so no `--auto` flag needed.

## Acceptance Criteria

- [x] `worktree-manager.sh cleanup-merged` detects branches with `[gone]` status using `git for-each-ref`
- [x] TTY detection: verbose output in terminal, quiet otherwise
- [x] Spec directories archived to `knowledge-base/specs/archive/YYYY-MM-DD-HHMMSS-<name>/`
- [x] Branch names with `/` are sanitized for archive paths
- [x] Currently active worktrees are skipped with warning
- [x] Worktrees with uncommitted changes are skipped (safety)
- [x] Local branches deleted after worktree removal (safe delete)
- [x] SessionStart hook triggers cleanup automatically
- [x] Network failure during fetch handled gracefully (warn and exit)
- [x] Operation failures are reported, not silently swallowed
- [x] Help text updated with new command

## Technical Considerations

### Edge Cases Handled

| Edge Case | Behavior |
|-----------|----------|
| No network (fetch fails) | Warn (if TTY) and exit cleanly |
| Active worktree | Skip with warning |
| Uncommitted changes in worktree | Skip with warning (safety) |
| Spec dir doesn't exist | Clean worktree anyway |
| Worktree doesn't exist | Delete branch anyway |
| Branch name contains `/` | Sanitized to `-` for archive path |
| Branch has local-only commits | `git branch -d` fails safely, branch preserved |
| Operation failures | Report warning, continue with next branch |

### Deferred to Future (YAGNI)

- `.worktree-keep` marker file for preventing auto-cleanup
- `--dry-run` flag for preview
- Audit logging of deletions
- Recovery mechanism for accidentally cleaned worktrees
- Distinguishing PR merge vs PR close (both show `[gone]`)
- PostToolUse hook for immediate post-merge cleanup (add if SessionStart is insufficient)

## Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| False positive from PR close | Acceptable - specs archived regardless, user can recover from archive |
| Hook timeout on slow cleanup | Cleanup should be fast (< 5s typical) |
| Race condition between hooks | Idempotent operations - safe to run twice |

## Success Metrics

- Zero manual worktree cleanup required for merged PRs
- Users see notification when cleanup occurs
- No data loss from auto-cleanup

## References & Research

### Internal References

- Current cleanup function: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:276`
- Spec workflow learnings: `knowledge-base/learnings/2026-02-06-spec-workflow-implementation.md:68`
- Brainstorm: `knowledge-base/brainstorms/2026-02-06-auto-cleanup-worktrees-brainstorm.md`
- Spec: `knowledge-base/specs/feat-auto-cleanup-worktrees/spec.md`

### Related Work

- Issue: #15
- Original request: #10
