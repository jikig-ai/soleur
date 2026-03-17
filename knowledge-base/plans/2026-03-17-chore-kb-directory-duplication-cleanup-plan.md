---
title: "chore: clean up knowledge-base directory duplication and leftover artifacts"
type: chore
date: 2026-03-17
semver: patch
deepened: 2026-03-17
---

# chore: clean up knowledge-base directory duplication and leftover artifacts

## Enhancement Summary

**Deepened on:** 2026-03-17
**Sections enhanced:** 6 (collision verification, spec overlap resolution, git mv edge cases, README update, archive-kb fallback cleanup, implementation script)
**Research method:** Exhaustive filesystem audit, learning corpus analysis, cross-reference verification

### Key Improvements
1. **Verified zero filename collisions** across all archive directories and all flat file directories -- `comm` checks confirm completely disjoint file sets between `project/` and root-level locations
2. **Resolved spec directory overlap** -- `feat-plausible-goals` and `feat-weekly-analytics-improvements` have complementary files (project/ has `tasks.md`, root has `session-state.md`), so merging is a simple `git mv` of individual files, not a content comparison
3. **Discovered missing documentation update** -- `knowledge-base/project/README.md` lines 132-137 still document the old `project/brainstorms/`, `project/learnings/`, etc. structure and must be updated alongside `components/knowledge-base.md`
4. **Applied learning: `git add` before `git mv`** -- per `2026-02-24-git-add-before-git-mv-for-untracked-files.md`, prepend `git add` on source files to handle any untracked files created during the session
5. **Identified post-cleanup optimization** -- after consolidation, `archive-kb.sh` and `worktree-manager.sh` legacy fallback paths (`knowledge-base/project/`, `knowledge-base/features/`) become dead code; flagged as separate follow-up, not in scope here

### New Considerations Discovered
- The `knowledge-base/project/specs/external/` directory needs to be checked -- if root `specs/` already has an `external/` dir, contents must merge
- Per learning `2026-03-13-stale-cross-references-after-kb-restructuring.md`, run a post-move grep sweep to catch any cross-references within the moved documents that point to `knowledge-base/project/` paths
- Single-commit approach is better than per-phase commits -- constitution says "single atomic commit that can be reverted with `git revert`", and splitting into 5 commits complicates revert

## Overview

After the KB restructure sequence (PRs #566, #570, #573, #581, #602, #606), three categories of leftover artifacts remain:

1. **`knowledge-base/project/` still contains brainstorms/ (28 files), learnings/ (180+ files), plans/ (84 files), and specs/ (84 dirs)** that should have been consolidated into the root-level canonical locations
2. **`knowledge-base/features/specs/`** is a ghost directory from PR #573 (moved to `features/`) that PR #581 only partially reversed -- 2 feat dirs and an archive dir remain
3. **Skills correctly reference root-level paths** (`knowledge-base/brainstorms/`, `knowledge-base/learnings/`, `knowledge-base/plans/`, `knowledge-base/specs/`) after PR #606 cleanup, but the stale `project/` subdirectories cause confusion about which location is canonical

## Problem Statement

The restructure history created a confusing state:

| Directory | Status | File Count | Canonical? |
|-----------|--------|------------|------------|
| `knowledge-base/brainstorms/` | Active, new files written here | 5 | Yes |
| `knowledge-base/project/brainstorms/` | Stale, no new files since 2026-03-13 | 28 + archive | No |
| `knowledge-base/learnings/` | Active, new files written here | 18 | Yes |
| `knowledge-base/project/learnings/` | Stale, no new files since 2026-03-13 | 180+ (flat + 12 subdirs) | No |
| `knowledge-base/plans/` | Active, new files written here | 16 + archive | Yes |
| `knowledge-base/project/plans/` | Stale, no new files since 2026-03-13 | 84 + archive | No |
| `knowledge-base/specs/` | Active, new specs created here | 18 dirs + archive | Yes |
| `knowledge-base/project/specs/` | Stale, no new specs since 2026-03-13 | 84 dirs + archive | No |
| `knowledge-base/features/specs/` | Ghost from PR #573 | 2 dirs + archive | No |

No files overlap between root-level and `project/` locations (different date ranges -- `project/` holds pre-March-13 content, root-level holds post-March-13 content). The `features/specs/` dirs (`feat-linkedin-presence`, `feat-ralph-loop-idle-detection`) are unique -- not duplicated at the root.

## Non-Goals

- Changing the canonical directory structure (root-level stays canonical)
- Updating skill/plugin path references (already correct after #606)
- Removing `knowledge-base/project/constitution.md`, `knowledge-base/project/README.md`, or `knowledge-base/project/components/` (these are intentionally at this location)
- Updating content inside archived/historical files

## Proposed Solution

Consolidate all stale `project/` subdirectories and `features/` leftovers into the canonical root-level directories using `git mv`, then remove the empty parent directories. All moves in a single atomic commit for clean `git revert` capability.

### Research Insights -- Commit Strategy

The original plan said "single atomic commit per phase" but this contradicts the constitution rule on line 85: "Operations that modify the knowledge-base or move files must use `git mv` to preserve history and produce a single atomic commit that can be reverted with `git revert`." A single commit across all phases is the correct approach. Splitting into 5+ commits means `git revert` requires reverting a range (`HEAD~N..HEAD`), which is error-prone.

### Phase 1: Merge `knowledge-base/features/specs/` into `knowledge-base/specs/`

The `features/specs/` directory has 2 feat dirs and an archive dir that need to merge into root `specs/`.

```text
knowledge-base/features/specs/feat-linkedin-presence/ -> knowledge-base/specs/feat-linkedin-presence/
knowledge-base/features/specs/feat-ralph-loop-idle-detection/ -> knowledge-base/specs/feat-ralph-loop-idle-detection/
knowledge-base/features/specs/archive/ -> merge contents into knowledge-base/specs/archive/
```

After moves, remove `knowledge-base/features/` entirely (it will be empty).

### Phase 2: Merge `knowledge-base/project/brainstorms/` into `knowledge-base/brainstorms/`

Move all files from `project/brainstorms/` (28 files + archive/) into `knowledge-base/brainstorms/`. No filename collisions exist (different date ranges).

```text
knowledge-base/project/brainstorms/*.md -> knowledge-base/brainstorms/
knowledge-base/project/brainstorms/archive/ -> merge into knowledge-base/brainstorms/archive/
```

### Phase 3: Merge `knowledge-base/project/learnings/` into `knowledge-base/learnings/`

Move all files and subdirectories from `project/learnings/` into `knowledge-base/learnings/`. The root-level `learnings/` currently has no subdirectories, while `project/learnings/` has 12 category subdirectories (`bug-fixes/`, `build-errors/`, `docs-site/`, `implementation-patterns/`, `integration-issues/`, `logic-errors/`, `performance-issues/`, `runtime-errors/`, `technical-debt/`, `ui-bugs/`, `workflow-issues/`, `workflow-patterns/`).

```text
knowledge-base/project/learnings/*.md -> knowledge-base/learnings/
knowledge-base/project/learnings/<category>/ -> knowledge-base/learnings/<category>/
```

### Phase 4: Merge `knowledge-base/project/plans/` into `knowledge-base/plans/`

Move all files from `project/plans/` (84 files + archive/) into `knowledge-base/plans/`. No filename collisions exist.

```text
knowledge-base/project/plans/*.md -> knowledge-base/plans/
knowledge-base/project/plans/archive/ -> merge into knowledge-base/plans/archive/
```

### Phase 5: Merge `knowledge-base/project/specs/` into `knowledge-base/specs/`

Move all spec directories from `project/specs/` (84 dirs + archive + external) into `knowledge-base/specs/`. Two directories overlap: `feat-plausible-goals` and `feat-weekly-analytics-improvements` exist in both locations.

```text
knowledge-base/project/specs/feat-*/ -> knowledge-base/specs/feat-*/  (non-overlapping dirs: direct move)
knowledge-base/project/specs/feat-plausible-goals/ -> MERGE with knowledge-base/specs/feat-plausible-goals/
knowledge-base/project/specs/feat-weekly-analytics-improvements/ -> MERGE with knowledge-base/specs/feat-weekly-analytics-improvements/
knowledge-base/project/specs/archive/ -> merge into knowledge-base/specs/archive/
knowledge-base/project/specs/external/ -> knowledge-base/specs/external/
```

### Research Insights -- Spec Overlap Resolution (Verified)

The two overlapping spec directories have **complementary, non-conflicting files**:

| Directory | `project/specs/` has | root `specs/` has |
|-----------|---------------------|-------------------|
| `feat-plausible-goals` | `tasks.md` | `session-state.md` |
| `feat-weekly-analytics-improvements` | `tasks.md` | `session-state.md` |

No file-level conflicts exist. The merge is a simple `git mv` of `tasks.md` from `project/specs/<dir>/` into the existing root `specs/<dir>/` -- no content comparison or manual resolution needed.

### Phase 6: Update Documentation

After moves, two documentation files need updating:

**6a. `knowledge-base/project/components/knowledge-base.md`** -- Lines 29-43 document the old directory structure with `project/brainstorms/`, `project/learnings/`, etc. Update the directory tree, examples (lines 158-165), and Related Files section (lines 184-188) to reflect the consolidated structure.

**6b. `knowledge-base/project/README.md`** -- Lines 132-137 document the old structure:
```text
  knowledge-base/           # Project documentation
    project/                # Project meta + feature lifecycle
      constitution.md       # Coding conventions
      brainstorms/          # Design explorations   <-- STALE
      learnings/            # Documented solutions  <-- STALE
      plans/                # Implementation plans  <-- STALE
      specs/                # Feature specifications <-- STALE
```
Update to show brainstorms/, learnings/, plans/, specs/ as direct children of `knowledge-base/`, not `project/`.

### Phase 7: Verification

```bash
# Verify project/ only contains constitution.md, README.md, components/
ls knowledge-base/project/

# Verify no empty directories remain
find knowledge-base/project/ -type d -empty

# Verify features/ is gone
test ! -d knowledge-base/features/ && echo "PASS"

# Verify all canonical dirs have content
ls knowledge-base/brainstorms/ | wc -l
ls knowledge-base/learnings/ | wc -l
ls knowledge-base/plans/ | wc -l
ls knowledge-base/specs/ | wc -l

# Verify no duplicate filenames across archive dirs
# (archive dirs from project/ and root should not have collisions)
```

## Technical Considerations

### Archive Directory Merging (Verified: Zero Collisions)

Both root-level and `project/` locations have `archive/` subdirectories for brainstorms, plans, and specs. **Exhaustive `comm -12` verification confirms zero filename collisions across all three archive directory pairs.** Archive files use timestamp-prefixed filenames (`20260313-091752-...`), and the two locations have completely disjoint date ranges.

The `features/specs/archive/` directory has one entry (`20260313-130805-feat-utm-conventions`) that also does not collide with root `specs/archive/`.

### Spec Directory Overlap (Verified: Complementary Files)

Two spec directories exist in both locations. Verified contents:
- `feat-plausible-goals`: project/ has `tasks.md`, root has `session-state.md` -- complementary, no conflict
- `feat-weekly-analytics-improvements`: project/ has `tasks.md`, root has `session-state.md` -- complementary, no conflict

Merge approach: `git mv` each `tasks.md` into the root spec dir alongside the existing `session-state.md`.

### Git History Preservation

All moves must use `git mv` per constitution rule. Per learning `2026-02-24-git-add-before-git-mv-for-untracked-files.md`, prepend `git add` on source files before `git mv` to handle any untracked files. `git add` on already-tracked files is a no-op, so this is safe to run unconditionally.

The entire operation should be a single commit for clean `git revert HEAD` capability.

### Learnings Category Subdirectories

The `project/learnings/` directory has 12 category subdirectories that do not exist in root `learnings/`. These need to be moved intact. The `learnings-researcher` agent's routing table already references `knowledge-base/learnings/<category>/` paths (updated in #606), so the categories landing in the root learnings/ directory is correct.

### External Specs Directory

`knowledge-base/project/specs/external/` may exist. Check whether root `knowledge-base/specs/` already has an `external/` directory. If not, the move is straightforward. If both exist, merge contents (same collision-check approach as archives).

### Post-Move Cross-Reference Sweep

Per learning `2026-03-13-stale-cross-references-after-kb-restructuring.md`: when restructuring directories that are cross-referenced by other documents, run `grep -r` to find references to old paths. After the move, run:

```bash
# Check for stale project/ paths in non-archive KB docs
grep -rn 'knowledge-base/project/' knowledge-base/ --include='*.md' \
  | grep -v '/archive/' \
  | grep -v '/project/constitution.md' \
  | grep -v '/project/README.md' \
  | grep -v '/project/components/' \
  | head -20
```

Any hits indicate cross-references within moved documents that still point to the old location. These are documentation-only (not executable), but updating them prevents future confusion.

### Shell Script Fallback Paths (Post-Cleanup Follow-up)

After consolidation, the legacy fallback paths in `archive-kb.sh` (lines 100-102, 113-114) and `worktree-manager.sh` (lines 495-496, 520-522) referencing `knowledge-base/project/` and `knowledge-base/features/` become dead code. With `nullglob`, they silently iterate zero times -- functionally harmless but technically dead. Flag as a separate cleanup issue, not in scope for this PR.

### Implementation Script

The move operation involves 380+ files. Rather than running individual `git mv` commands, use a scripted approach:

```bash
# Phase 1: features/specs/
git add knowledge-base/features/specs/
git mv knowledge-base/features/specs/feat-linkedin-presence knowledge-base/specs/
git mv knowledge-base/features/specs/feat-ralph-loop-idle-detection knowledge-base/specs/
git mv knowledge-base/features/specs/archive/20260313-130805-feat-utm-conventions knowledge-base/specs/archive/

# Phase 2: project/brainstorms/
git add knowledge-base/project/brainstorms/
for f in knowledge-base/project/brainstorms/*.md; do git mv "$f" knowledge-base/brainstorms/; done
for f in knowledge-base/project/brainstorms/archive/*; do git mv "$f" knowledge-base/brainstorms/archive/; done

# Phase 3: project/learnings/ (flat files + category subdirs)
git add knowledge-base/project/learnings/
for f in knowledge-base/project/learnings/*.md; do git mv "$f" knowledge-base/learnings/; done
for dir in knowledge-base/project/learnings/*/; do
  dirname=$(basename "$dir")
  git mv "$dir" "knowledge-base/learnings/$dirname"
done

# Phase 4: project/plans/
git add knowledge-base/project/plans/
for f in knowledge-base/project/plans/*.md; do git mv "$f" knowledge-base/plans/; done
for f in knowledge-base/project/plans/archive/*; do git mv "$f" knowledge-base/plans/archive/; done

# Phase 5: project/specs/ (non-overlapping dirs first)
git add knowledge-base/project/specs/
for dir in knowledge-base/project/specs/feat-*/; do
  dirname=$(basename "$dir")
  if [[ -d "knowledge-base/specs/$dirname" ]]; then
    # Overlapping dir -- move individual files
    for f in "$dir"*; do
      [[ -f "$f" ]] && git mv "$f" "knowledge-base/specs/$dirname/"
    done
  else
    git mv "$dir" "knowledge-base/specs/"
  fi
done
# Archive and external
for f in knowledge-base/project/specs/archive/*; do git mv "$f" knowledge-base/specs/archive/; done
if [[ -d knowledge-base/project/specs/external ]]; then
  git mv knowledge-base/project/specs/external knowledge-base/specs/
fi

# Cleanup empty dirs (git rm removes empty dirs automatically on next commit)
```

## Acceptance Criteria

- [ ] `knowledge-base/project/` contains ONLY: `constitution.md`, `README.md`, `components/`
- [ ] `knowledge-base/features/` directory does not exist
- [ ] `knowledge-base/brainstorms/` contains all 33+ brainstorm files (5 root + 28 project/)
- [ ] `knowledge-base/learnings/` contains all 198+ learning files including 12 category subdirectories
- [ ] `knowledge-base/plans/` contains all 100+ plan files (16 root + 84 project/)
- [ ] `knowledge-base/specs/` contains all 104+ spec directories (18 root + 84 project/ + 2 features/)
- [ ] `feat-plausible-goals` spec dir contains both `tasks.md` and `session-state.md`
- [ ] `feat-weekly-analytics-improvements` spec dir contains both `tasks.md` and `session-state.md`
- [ ] No duplicate files exist (same filename in multiple locations)
- [ ] `git log --follow` works on moved files (history preserved via `git mv`)
- [ ] `knowledge-base/project/components/knowledge-base.md` directory tree updated
- [ ] `knowledge-base/project/README.md` directory structure updated (lines 132-137)
- [ ] All changes in a single atomic commit

## Test Scenarios

- Given the cleanup is complete, when running `ls knowledge-base/project/`, then only `constitution.md`, `README.md`, and `components/` are listed
- Given the cleanup is complete, when running `ls knowledge-base/features/`, then the command fails (directory does not exist)
- Given the cleanup is complete, when running `ls knowledge-base/learnings/bug-fixes/`, then category files from the old `project/learnings/bug-fixes/` are present
- Given the cleanup is complete, when the learnings-researcher agent searches `knowledge-base/learnings/implementation-patterns/`, then it finds the pattern files that were previously under `project/learnings/implementation-patterns/`
- Given the cleanup is complete, when running `ls knowledge-base/specs/feat-plausible-goals/`, then both `tasks.md` and `session-state.md` are present (merged from project/ and root)
- Given the cleanup is complete, when the archive-kb.sh script runs, then it discovers artifacts at the canonical root-level paths (no change from current behavior)
- Given the cleanup is complete, when checking `git log --follow` on a moved file, then the pre-move commit history is visible
- Given the cleanup is complete, when running `wc -l` on `knowledge-base/brainstorms/`, then the count is >= 33 (5 root + 28 from project/)
- Given the cleanup is complete, when running `grep -rn 'knowledge-base/project/' knowledge-base/project/README.md`, then only references to `constitution.md`, `README.md`, and `components/` remain (no brainstorms/learnings/plans/specs references)
- Given the cleanup is committed as a single commit, when running `git revert HEAD`, then the split state is cleanly restored

## Rollback Plan

`git revert HEAD` cleanly undoes all `git mv` operations, restoring the split state. No runtime behavior changes -- skills already point to root-level paths.

## Dependencies & Risks

### Risk: Large diff

Moving 380+ files produces a large diff. Using `git mv` ensures git tracks renames, but the PR diff will be large. GitHub may truncate the diff view. Mitigate by keeping the move commit separate from the documentation update commit if reviewability is a concern -- though the constitution prefers a single atomic commit.

### Risk: Concurrent worktree conflicts

Other active worktrees (`feat-653-growth-audit-p1`, `feat-ralph-loop-session-scope`, `feat-web-platform-ux`) may reference files in `knowledge-base/project/`. After this PR merges, those branches will need to merge origin/main and resolve any path conflicts. The pre-merge-rebase hook enforces this.

### Risk: git mv directory into existing directory

When running `git mv knowledge-base/project/specs/feat-xxx knowledge-base/specs/`, if `knowledge-base/specs/feat-xxx` does not already exist, git creates it. If it does exist (the 2 overlapping dirs), `git mv` of the directory fails with "destination already exists". The implementation script handles this by moving individual files from overlapping directories rather than the directory itself.

### Dependency: No skill changes needed

Skills already reference canonical root-level paths after #606. This cleanup only moves physical files -- no code changes required in plugins/.

### Dependency: archive-kb.sh and worktree-manager.sh fallback paths

Both scripts search `knowledge-base/project/` and `knowledge-base/features/` as legacy fallback paths. After this cleanup, those directories (or their artifact subdirectories) will no longer exist. The scripts handle this gracefully via `nullglob` -- nonexistent directories simply produce zero glob matches. No script changes needed for this PR.

## Semver Intent

`semver:patch` -- internal file consolidation, no user-facing behavior change.

## Relevant Learnings Applied

1. **`2026-02-24-git-add-before-git-mv-for-untracked-files.md`**: Always `git add` before `git mv` to handle untracked files. Applied in the implementation script -- each phase prepends `git add` on source directories.
2. **`2026-03-13-archive-kb-stale-path-resolution.md`**: Shell scripts with hardcoded paths fail silently after directory restructures. Confirmed that `archive-kb.sh` and `worktree-manager.sh` already have fallback arrays (from #602) that will gracefully handle the removal of legacy paths.
3. **`2026-03-13-stale-cross-references-after-kb-restructuring.md`**: Always run `grep -r` for old paths after a move. Added post-move cross-reference sweep to verification phase.
4. **`2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`**: Past silent archiving failure affected 92 artifacts. This cleanup consolidates the remaining artifacts from that era into canonical locations where they will be discoverable.
5. **`2026-02-06-docs-consolidation-migration.md`**: The original migration that created `knowledge-base/` updated 103 path references. This cleanup is the final step in that consolidation -- moving the last 380+ files that ended up split across locations.

## References

- KB restructure sequence: #566, #570, #573, #581, #602, #606
- Issue #568 (group under features/ -- shipped then reversed)
- Issue #569/#570 (overview/ to project/ rename)
- Issue #604 (stale reference cleanup in SKILL.md files)
- Learning: `knowledge-base/learnings/2026-03-13-archive-kb-stale-path-resolution.md`
- Learning: `knowledge-base/project/learnings/2026-02-24-git-add-before-git-mv-for-untracked-files.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-stale-cross-references-after-kb-restructuring.md`
- Learning: `knowledge-base/project/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`
- Learning: `knowledge-base/project/learnings/2026-02-06-docs-consolidation-migration.md`
- Constitution: `knowledge-base/project/constitution.md` (lines 85-86 on `git mv` requirements)
