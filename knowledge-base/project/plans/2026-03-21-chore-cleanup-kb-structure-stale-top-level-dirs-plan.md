---
title: "chore: remove stale top-level knowledge-base directories and add prevention guard"
type: chore
date: 2026-03-21
related_prs: [657, 897]
deepened: 2026-03-21
---

# chore: Clean Up Stale Top-Level Knowledge-Base Directories

## Enhancement Summary

**Deepened on:** 2026-03-21
**Sections enhanced:** 3 (Phase 1, Phase 2, Phase 4)

### Key Improvements

1. Fixed Lefthook glob pattern -- `**` in gobwas requires 1+ directory levels, so files directly in `knowledge-base/brainstorms/*.md` would silently pass the proposed guard. Corrected to use array glob with both `*` and `**/*` patterns.
2. Added git mv edge case handling for nested subdirectories (`build-errors/`, `archive/`) that need `mkdir -p` before move.
3. Added sed dry-run verification step to catch false-positive replacements before committing.

### Applicable Learnings

- `knowledge-base/project/learnings/2026-03-21-lefthook-gobwas-glob-double-star.md` -- gobwas `**` matches 1+ dirs, not 0+. Directly impacts Phase 4 guard design.
- `knowledge-base/project/learnings/workflow-issues/2026-03-20-verify-both-source-and-dest-before-migration-planning.md` -- verify both source AND destination before migration. Applied: scope is accurate (144 files, 0 duplicates confirmed).

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
        # Ensure target parent exists (needed for nested subdirs like build-errors/, archive/)
        mkdir -p "$(dirname "$target")"
        git mv "$item" "knowledge-base/project/$type/"
      fi
    done
  fi
done
```

### Research Insights (Phase 1)

**Edge Cases:**
- **Nested subdirectories**: `learnings/build-errors/` and `plans/archive/` are
  nested within their parent. The `mkdir -p` ensures the target parent exists
  before `git mv`. Without it, `git mv` will fail with "destination does not exist".
- **Empty glob expansion**: If a directory is empty, `knowledge-base/$type/*`
  expands to the literal string. The `[[ -d "$item" ]]` check inside the loop
  handles this, but wrapping in `shopt -s nullglob` before the loop and
  `shopt -u nullglob` after is safer to prevent the literal-string case.
- **Git mv atomicity**: Each `git mv` is atomic but the loop is not. If it fails
  midway, some files will be in the old location and some in the new. This is
  safe because the script can be re-run -- it skips already-moved files
  (they no longer exist at the source).

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

### Research Insights (Phase 2)

**Dry-run verification before committing sed changes:**

Run the sed with `--quiet` + `p` flag first to preview what would change without
modifying files:

```bash
find knowledge-base/project/{brainstorms,learnings,plans,specs} \
     -name '*.md' -exec grep -l \
     -e 'knowledge-base/brainstorms/' \
     -e 'knowledge-base/learnings/' \
     -e 'knowledge-base/plans/' \
     -e 'knowledge-base/specs/' {} + \
     | grep -v 'knowledge-base/project/' \
     | head -5
```

If this returns 0 files, all references are already correct and Phase 2 can be
skipped. If it returns files, those are the ones sed needs to touch.

**Double-prefix safety (verified):** Tested empirically -- `sed 's|knowledge-base/brainstorms/|knowledge-base/project/brainstorms/|g'`
applied to the string `knowledge-base/project/brainstorms/foo.md` produces
`knowledge-base/project/brainstorms/foo.md` (unchanged). The pattern
`knowledge-base/brainstorms/` is NOT a substring of `knowledge-base/project/brainstorms/`
because `project/` sits between the two segments.

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
  glob:
    - "knowledge-base/{brainstorms,learnings,plans,specs}/*"
    - "knowledge-base/{brainstorms,learnings,plans,specs}/**/*"
  run: |
    echo "ERROR: Files staged at deprecated knowledge-base paths." >&2
    echo "Move to knowledge-base/project/ before committing:" >&2
    echo "  knowledge-base/{brainstorms,learnings,plans,specs}/ -> knowledge-base/project/{brainstorms,learnings,plans,specs}/" >&2
    exit 1
```

**Why Lefthook**: The project already uses Lefthook for pre-commit hooks
(`lefthook.yml` has 7 existing commands). A glob-based guard is the lightest
enforcement that catches the problem at commit time, before files reach `main`.

### Research Insights (Phase 4) -- CRITICAL FIX

**Lefthook gobwas glob `**` gotcha (from documented learning):**

The original plan used `glob: "knowledge-base/{brainstorms,...}/**"` which has
a silent failure mode. Lefthook's default glob matcher (gobwas/glob) requires
`**` to match 1+ directory levels, unlike bash/ripgrep where `**` matches 0+.

This means:
- `knowledge-base/brainstorms/**` matches `knowledge-base/brainstorms/subdir/file.md`
- `knowledge-base/brainstorms/**` does NOT match `knowledge-base/brainstorms/file.md`

75 of the 144 files sit directly in their type directory (no subdirectory), so
the original glob would miss them entirely. The hook would run but match zero
files and silently succeed ("skip: no files for inspection").

**Fix:** Use an array glob (supported since Lefthook 1.10.10; installed version
is 2.1.4) with both `*` (direct files) and `**/*` (nested files):

```yaml
glob:
  - "knowledge-base/{brainstorms,learnings,plans,specs}/*"
  - "knowledge-base/{brainstorms,learnings,plans,specs}/**/*"
```

**Testing the guard:** After adding the hook, verify with:
```bash
# Create a dummy file at an old path
touch knowledge-base/brainstorms/test-guard.md
git add knowledge-base/brainstorms/test-guard.md
# This should fail with the guard error
git commit -m "test: verify kb-structure-guard"
# Clean up
git reset HEAD knowledge-base/brainstorms/test-guard.md
rm knowledge-base/brainstorms/test-guard.md
```

**Reference:** `knowledge-base/project/learnings/2026-03-21-lefthook-gobwas-glob-double-star.md`

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
| Lefthook glob doesn't match | Low (was Medium) | Array glob with `*` + `**/*` covers both direct files and nested files. gobwas `**` gotcha addressed per documented learning. Test with dummy file to verify. |
| Cached system prompts bypass guard | Medium | Guard runs at commit time, not at file write time -- catches the problem before merge |

## Non-Goals

- Restructuring the domain directories (`engineering/`, `marketing/`, etc.) -- these are correctly placed
- Modifying skill SKILL.md files -- they already use correct paths
- Modifying agent definitions -- they already use correct paths
- Adding CI-level path guards (Lefthook is sufficient since all commits go through local hooks with Claude Code sessions; if external contributors join later, a GitHub Actions path check should be added as defense-in-depth)
