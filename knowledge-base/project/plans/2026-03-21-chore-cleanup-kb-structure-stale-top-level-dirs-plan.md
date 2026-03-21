---
title: "chore: remove stale top-level knowledge-base directories and add prevention guard"
type: chore
date: 2026-03-21
related_prs: [657, 897]
---

# chore: Clean Up Stale Top-Level Knowledge-Base Directories

## Problem

PRs #657 (merged 2026-03-17) and #897 (merged 2026-03-20) migrated all workflow
artifact directories (`brainstorms/`, `learnings/`, `plans/`, `specs/`) from
`knowledge-base/` to `knowledge-base/project/`. Both PRs updated every skill,
agent, script, and documentation reference to use the `project/` prefix.

Despite this, **144 files** still exist at the old top-level locations on `main`:

| Directory | File Count |
|-----------|-----------|
| `knowledge-base/brainstorms/` | 8 |
| `knowledge-base/learnings/` | 30 |
| `knowledge-base/plans/` | 39 |
| `knowledge-base/specs/` (56 subdirs) | 67 |
| **Total** | **144** |

### Root Cause

Feature branches created from `main` after the #657 merge but before #897
inherited the updated skill definitions but were already forked with their own
worktree copies. When agents in those sessions wrote artifact files, some used
paths from the system prompt cache (which reflected older SKILL.md versions)
rather than the on-disk SKILL.md. When these branches merged to `main` via
squash merge, they re-created the top-level directories.

Every commit that added files to old locations occurred AFTER #897 merged --
confirming this is a re-creation problem, not a missed migration.

### Why Prior Fixes Did Not Stick

1. **No prevention guard**: Nothing blocks commits that create files at old
   locations. The migration runs, then the next batch of feature branches
   undoes it.
2. **No deduplication check**: The skill SKILL.md files direct writes to
   `knowledge-base/project/`, but the Claude system prompt loaded at session
   start may be cached from a prior session or a different worktree checkout.
   The agent follows the system prompt, not the on-disk file.

## Scope

### Files to Move (144 total, 0 duplicates in project/)

All files are unique to the old location -- none have counterparts in
`knowledge-base/project/` except for one spec directory
(`fix-playwright-version-mismatch/`) which has `session-state.md` at the old
path and `tasks.md` at the new path. These need merging.

### Internal References to Update

- **92 cross-references** within the 144 misplaced files reference old paths
  (e.g., `knowledge-base/plans/...` instead of `knowledge-base/project/plans/...`)
- **0 references** in `knowledge-base/project/` files point to old paths
- **1 reference** in `spike/agent-sdk-test.ts` uses an old test path

### Source Code Status

All operational files (SKILL.md, agents, scripts, shell tools) already reference
`knowledge-base/project/`. No source code changes needed for the migration
itself -- only the file move, reference fixup inside moved files, and a
prevention guard.

## Implementation Plan

### Phase 1: Move Files (git mv)

Use `git mv` for all 144 files to preserve history:

1. **brainstorms/**: Move 8 files to `knowledge-base/project/brainstorms/`
2. **learnings/**: Move 30 files (including `build-errors/` subdir with 1 file)
   to `knowledge-base/project/learnings/`
3. **plans/**: Move 39 files to `knowledge-base/project/plans/`; the
   `plans/archive/` subdir (1 file) goes to `knowledge-base/project/plans/archive/`
4. **specs/**: Move 56 subdirectories (67 files) to `knowledge-base/project/specs/`
   - Special case: `fix-playwright-version-mismatch/session-state.md` moves to
     `knowledge-base/project/specs/fix-playwright-version-mismatch/session-state.md`
     (the existing `tasks.md` stays)

Script approach:
```bash
# Move each artifact type
for type in brainstorms learnings plans specs; do
  if [[ -d "knowledge-base/$type" ]]; then
    # Use git mv for each file/dir to preserve history
    for item in knowledge-base/$type/*; do
      target="knowledge-base/project/$type/$(basename "$item")"
      if [[ -d "$item" ]] && [[ -d "$target" ]]; then
        # Merge: move individual files from source dir into existing target dir
        for f in "$item"/*; do
          [[ -e "$f" ]] && git mv "$f" "$target/"
        done
        rmdir "$item" 2>/dev/null || true
      else
        git mv "$item" "knowledge-base/project/$type/"
      fi
    done
  fi
done
```

### Phase 2: Fix Internal References (sed)

After moving, update the 92 stale references within the moved files:

```bash
find knowledge-base/project/brainstorms knowledge-base/project/learnings \
     knowledge-base/project/plans knowledge-base/project/specs \
     -name '*.md' -exec sed -i \
     -e 's|knowledge-base/brainstorms/|knowledge-base/project/brainstorms/|g' \
     -e 's|knowledge-base/learnings/|knowledge-base/project/learnings/|g' \
     -e 's|knowledge-base/plans/|knowledge-base/project/plans/|g' \
     -e 's|knowledge-base/specs/|knowledge-base/project/specs/|g' \
     {} +
```

**Important**: The sed patterns must NOT match `knowledge-base/project/` (which
already contains the correct path). The replacement patterns are safe because
`knowledge-base/brainstorms/` will NOT match `knowledge-base/project/brainstorms/`
-- the `project/` segment breaks the match.

Also fix `spike/agent-sdk-test.ts`:
```bash
sed -i 's|knowledge-base/brainstorms/|knowledge-base/project/brainstorms/|g' \
  spike/agent-sdk-test.ts
```

### Phase 3: Remove Empty Directories

After all files are moved, remove the now-empty top-level directories:

```bash
rmdir knowledge-base/brainstorms knowledge-base/learnings/build-errors \
      knowledge-base/learnings knowledge-base/plans/archive \
      knowledge-base/plans knowledge-base/specs/* knowledge-base/specs \
      2>/dev/null
```

### Phase 4: Add Prevention Guard (Lefthook pre-commit hook)

Add a new Lefthook pre-commit command that rejects commits containing files at
the old top-level paths. This is the critical missing piece that caused PRs #657
and #897 to be undone:

```yaml
# In lefthook.yml, add:
kb-structure-guard:
  priority: 8
  glob: "knowledge-base/{brainstorms,learnings,plans,specs}/**"
  run: |
    echo "ERROR: Files staged at deprecated knowledge-base paths." >&2
    echo "Move to knowledge-base/project/ before committing:" >&2
    echo "  knowledge-base/{brainstorms,learnings,plans,specs}/ -> knowledge-base/project/{brainstorms,learnings,plans,specs}/" >&2
    exit 1
```

**Why Lefthook**: The project already uses Lefthook for pre-commit hooks
(`lefthook.yml` has 7 existing commands). A glob-based guard is the lightest
enforcement that catches the problem at commit time, before files reach `main`.

### Phase 5: Update spike test reference

Fix the stale reference in `spike/agent-sdk-test.ts` (line 37) from
`knowledge-base/brainstorms/` to `knowledge-base/project/brainstorms/`.

### Phase 6: Verification

- [ ] `find knowledge-base/brainstorms knowledge-base/learnings knowledge-base/plans knowledge-base/specs -type f 2>/dev/null | wc -l` returns 0
- [ ] `find knowledge-base/project/brainstorms knowledge-base/project/learnings knowledge-base/project/plans knowledge-base/project/specs -type f | wc -l` equals or exceeds previous total
- [ ] `grep -r 'knowledge-base/brainstorms\|knowledge-base/learnings\|knowledge-base/plans\|knowledge-base/specs' --include='*.md' knowledge-base/project/ | grep -v 'knowledge-base/project/' | wc -l` returns 0
- [ ] `bun test plugins/soleur/test/` passes
- [ ] `git status` shows no untracked files in old locations
- [ ] Lefthook guard triggers on a test commit to an old path

## Acceptance Criteria

- [ ] Zero files exist at `knowledge-base/{brainstorms,learnings,plans,specs}/`
- [ ] All 144 files accessible at `knowledge-base/project/` counterparts
- [ ] All internal cross-references updated to `project/` paths
- [ ] Lefthook pre-commit guard blocks future writes to old paths
- [ ] All existing tests pass
- [ ] `fix-playwright-version-mismatch/` spec directory properly merged

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `git mv` breaks file history | Low | Use `git mv` (not `cp` + `rm`); verify with `git log --follow` |
| sed corrupts file content | Low | Patterns are specific; cannot match `project/` prefix |
| Lefthook glob doesn't match | Medium | Test with a dummy file before committing the guard |
| Cached system prompts bypass guard | Medium | Guard runs at commit time, not at file write time -- catches the problem before merge |

## Non-Goals

- Restructuring the domain directories (`engineering/`, `marketing/`, etc.) -- these are correctly placed
- Modifying skill SKILL.md files -- they already use correct paths
- Modifying agent definitions -- they already use correct paths
- Adding CI-level path guards (Lefthook is sufficient since all commits go through local hooks)
