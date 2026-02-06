---
title: "feat: Worktree Layer Enhancements"
type: feat
date: 2026-02-05
layer: worktree
priority: 2
dependencies:
  - 2026-02-05-feat-knowledge-base-foundation-plan.md
---

# Worktree Layer Enhancements

## Overview

Enhance the existing `git-worktree` skill to support the unified spec-driven workflow. Add automatic worktree creation at brainstorm start, interactive worktree switching, and auto-cleanup on merge.

## Problem Statement

The current `git-worktree` skill provides basic worktree management, but the new workflow needs:
- Automatic worktree creation when starting a feature (at brainstorm)
- Easy switching between active worktrees via interactive picker
- Automatic cleanup when PRs are merged
- Consistent naming convention (`feat-<name>`)
- Link between worktree and its spec in `knowledge-base/specs/`

## Proposed Solution

### 1. Enhance git-worktree skill

Update `plugins/soleur/skills/git-worktree/SKILL.md` to support:
- `create-for-feature <name>` - Creates worktree + corresponding spec directory
- `list-with-specs` - Shows worktrees with their spec status
- `cleanup-merged` - Removes worktrees for merged branches

### 2. Create soleur:switch command

New command `plugins/soleur/commands/soleur/switch.md` that:
- Lists all active worktrees with their feature names
- Shows spec status (has spec.md? has tasks.md?)
- Provides interactive selection (fzf-like)
- Changes to selected worktree directory

### 3. Auto-cleanup mechanism

Add cleanup check to `soleur:compound` that:
- Checks if current branch's PR is merged
- If merged, offers to clean up worktree
- Removes worktree and optionally archives spec

## Technical Approach

### Phase 1: Skill Enhancement

**Update:** `plugins/soleur/skills/git-worktree/SKILL.md`

Add new operations:

```markdown
## Operations

### create-for-feature
Creates a worktree for a new feature with corresponding spec directory.

**Usage:** `worktree-manager.sh create-for-feature <feature-name>`

**Actions:**
1. Creates branch `feat-<name>` from current HEAD
2. Creates worktree at `.worktrees/feat-<name>/`
3. Creates spec directory `knowledge-base/specs/feat-<name>/`
4. Copies `.env` if exists

### list-with-specs
Lists worktrees with their spec status.

**Output format:**
```
feat-auth       [spec.md tasks.md]  .worktrees/feat-auth/
feat-payment    [spec.md ---------]  .worktrees/feat-payment/
feat-search     [-------- ---------]  .worktrees/feat-search/
```

### cleanup-merged
Removes worktrees for branches that have been merged to main.

**Actions:**
1. Check each worktree's branch against main
2. If merged, remove worktree
3. Optionally archive spec to `knowledge-base/specs/archive/`
```

**Update:** `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

Add the three new operations to the shell script.

**Alternative: Bun script** (recommended for cross-platform consistency)

Consider `worktree-manager.ts` using Bun's shell API:

```typescript
// plugins/soleur/skills/git-worktree/scripts/worktree-manager.ts
import { $ } from "bun";

export async function createForFeature(name: string) {
  const branchName = `feat-${name}`;
  const worktreePath = `.worktrees/${branchName}`;
  const specPath = `knowledge-base/specs/${branchName}`;

  await $`git worktree add -b ${branchName} ${worktreePath}`;
  await $`mkdir -p ${specPath}`;
  // Copy .env if exists
  if (await Bun.file(".env").exists()) {
    await $`cp .env ${worktreePath}/.env`;
  }
}
```

This provides:
- Type safety and IDE support
- Cross-platform compatibility (Windows, Linux, macOS)
- Easier testing with Bun's test runner
- Consistent with Soleur's Bun/TypeScript stack

### Phase 2: Switch Command

**Create:** `plugins/soleur/commands/soleur/switch.md`

```yaml
---
name: switch
description: Interactively switch between active feature worktrees
---
```

**Behavior:**
1. Call `worktree-manager.sh list-with-specs`
2. Present options via AskUserQuestion with worktree details
3. On selection, output `cd` command or use shell integration

### Phase 3: Cleanup Integration

**Update:** `plugins/soleur/commands/soleur/compound.md`

Add cleanup check at end of compound flow:

```markdown
### Cleanup Check (at end of compound)

1. Check if current branch has merged PR: `gh pr list --state merged --head <branch>`
2. If merged, ask user: "PR merged. Clean up worktree?"
3. If yes, run `worktree-manager.sh cleanup-merged`
```

## Acceptance Criteria

- [ ] `worktree-manager.sh create-for-feature <name>` creates worktree + spec directory
- [ ] `worktree-manager.sh list-with-specs` shows worktrees with spec status
- [ ] `worktree-manager.sh cleanup-merged` removes merged worktrees
- [ ] `soleur:switch` command provides interactive worktree selection
- [ ] Worktrees are created at `.worktrees/feat-<name>/`
- [ ] Spec directories are created at `knowledge-base/specs/feat-<name>/`
- [ ] `soleur:compound` checks for merged PRs and offers cleanup

## Success Metrics

- Worktree creation is automatic when starting a feature
- Switching between features is a single command
- No orphaned worktrees for merged branches

## Test Strategy

- [ ] Unit test: `createForFeature` creates correct directory structure
- [ ] Unit test: `listWithSpecs` parses worktree output correctly
- [ ] Unit test: `cleanupMerged` identifies merged branches
- [ ] Integration test: Full create→switch→cleanup cycle in test repo
- [ ] Fixture: Mock git repo with multiple worktrees for testing

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/skills/git-worktree/SKILL.md` | Add new operations documentation |
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Implement new operations |
| `plugins/soleur/commands/soleur/compound.md` | Add cleanup check |

## Files to Create

| File | Purpose |
|------|---------|
| `plugins/soleur/commands/soleur/switch.md` | Interactive worktree switcher command |

## References

- Brainstorm: `docs/brainstorms/2026-02-05-unified-spec-workflow-brainstorm.md`
- Git Worktree Workflow section
- Existing skill: `plugins/soleur/skills/git-worktree/SKILL.md`
