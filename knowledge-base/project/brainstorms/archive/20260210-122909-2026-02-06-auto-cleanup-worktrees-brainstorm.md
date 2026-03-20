---
date: 2026-02-06
topic: auto-cleanup-worktrees
issue: "#10"
---

# Auto-Cleanup Worktrees After PR Merge

## What We're Building

Automatic cleanup of worktrees and associated spec directories when a PR is merged. The system will detect merged branches, remove the corresponding worktree from `.worktrees/`, archive the spec directory to `knowledge-base/specs/archive/`, and optionally delete the local branch.

Cleanup is triggered in two scenarios:
1. **Session start** - catches PRs merged via GitHub UI while user was away
2. **Post-merge hook** - catches PRs merged within the current Claude Code session

## Why This Approach

We considered three approaches:

| Approach | Complexity | Dependencies | Chosen |
|----------|------------|--------------|--------|
| A: Extend worktree-manager.sh | Low | None (uses git native) | Yes |
| B: Dedicated skill with state tracking | Medium | State file management | No |
| C: GitHub Actions webhook | High | GH Actions + coordination | No |

**Approach A wins** because:
- Builds on existing `worktree-manager.sh` infrastructure
- Uses git's native `[gone]` branch tracking (no custom state)
- Both triggers share the same cleanup logic
- YAGNI - simplest solution that works

## Key Decisions

- **Detection method**: Git's `[gone]` marker via `git branch -vv` after fetch
- **Spec handling**: Archive to `knowledge-base/specs/archive/YYYY-MM-DD-<name>/` (matches OpenSpec pattern)
- **User interaction**: Auto cleanup with notification summary (no confirmation prompts)
- **Branch deletion**: Delete local branch after worktree removal
- **Trigger 1**: Claude Code `SessionStart` hook runs `cleanup-merged --auto`
- **Trigger 2**: Claude Code `PostToolUse` hook on `gh pr merge` cleans specific branch

## Implementation Outline

### worktree-manager.sh additions

New command: `cleanup-merged [--auto] [branch-name]`

```
--auto      Silent mode, outputs summary only
branch-name Optional specific branch to clean (for post-merge hook)
```

Logic:
1. Run `git fetch --prune` to update remote tracking
2. Find branches with `[gone]` status: `git branch -vv | grep '\[gone\]'`
3. For each gone branch with matching worktree:
   - Archive `knowledge-base/specs/feat-<name>/` -> `knowledge-base/specs/archive/YYYY-MM-DD-feat-<name>/`
   - Run `git worktree remove .worktrees/feat-<name>`
   - Run `git branch -d feat-<name>`
4. Output summary of cleaned items

### Claude Code hooks

```json
{
  "hooks": [
    {
      "event": "SessionStart",
      "command": ["./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh", "cleanup-merged", "--auto"]
    },
    {
      "event": "PostToolUse",
      "matcher": {"tool": "Bash", "pattern": "gh pr merge"},
      "command": ["./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh", "cleanup-merged", "--auto"]
    }
  ]
}
```

## Open Questions

- Should cleanup respect a `.worktree-keep` marker file to prevent auto-cleanup of specific worktrees?
- What happens if spec directory has uncommitted changes? (Probably safe since PR was merged)

## Next Steps

-> `/soleur:plan` for implementation details
