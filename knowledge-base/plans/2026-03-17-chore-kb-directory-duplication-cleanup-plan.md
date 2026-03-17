---
title: "chore: clean up knowledge-base directory duplication and leftover artifacts"
type: chore
date: 2026-03-17
semver: patch
---

# chore: clean up knowledge-base directory duplication and leftover artifacts

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

Consolidate all stale `project/` subdirectories and `features/` leftovers into the canonical root-level directories using `git mv`, then remove the empty parent directories. Single atomic commit per phase.

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

Move all spec directories from `project/specs/` (84 dirs + archive + external) into `knowledge-base/specs/`. Two directories overlap: `feat-plausible-goals` and `feat-weekly-analytics-improvements` exist in both locations -- contents must be compared and merged carefully.

```text
knowledge-base/project/specs/feat-*/ -> knowledge-base/specs/feat-*/  (non-overlapping dirs: direct move)
knowledge-base/project/specs/feat-plausible-goals/ -> MERGE with knowledge-base/specs/feat-plausible-goals/
knowledge-base/project/specs/feat-weekly-analytics-improvements/ -> MERGE with knowledge-base/specs/feat-weekly-analytics-improvements/
knowledge-base/project/specs/archive/ -> merge into knowledge-base/specs/archive/
knowledge-base/project/specs/external/ -> knowledge-base/specs/external/
```

### Phase 6: Update `knowledge-base/project/components/knowledge-base.md`

After moves, the component documentation at `knowledge-base/project/components/knowledge-base.md` still documents the old directory structure with `project/brainstorms/`, `project/learnings/`, etc. Update the directory tree and references to reflect the consolidated structure.

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

### Archive Directory Merging

Both root-level and `project/` locations have `archive/` subdirectories for brainstorms, plans, and specs. Archive files use timestamp-prefixed filenames (`20260313-091752-...`), so collisions are extremely unlikely. Verify with a `comm` check before merging.

### Spec Directory Overlap

Two spec directories exist in both locations: `feat-plausible-goals` and `feat-weekly-analytics-improvements`. Compare contents (typically `spec.md`, `tasks.md`, `session-state.md`) and keep the most recent version of each file. If both have unique files, keep all.

### Git History Preservation

All moves must use `git mv` per constitution rule. The entire operation should be a single commit for clean revert capability.

### Learnings Category Subdirectories

The `project/learnings/` directory has 12 category subdirectories that do not exist in root `learnings/`. These need to be moved intact. The `learnings-researcher` agent's routing table already references `knowledge-base/learnings/<category>/` paths (updated in #606), so the categories landing in the root learnings/ directory is correct.

## Acceptance Criteria

- [ ] `knowledge-base/project/` contains ONLY: `constitution.md`, `README.md`, `components/`
- [ ] `knowledge-base/features/` directory does not exist
- [ ] `knowledge-base/brainstorms/` contains all brainstorm files (previously split between root and project/)
- [ ] `knowledge-base/learnings/` contains all learning files including 12 category subdirectories
- [ ] `knowledge-base/plans/` contains all plan files (previously split between root and project/)
- [ ] `knowledge-base/specs/` contains all spec directories (previously split between root, project/, and features/)
- [ ] No duplicate files exist (same filename in multiple locations)
- [ ] `git log --follow` works on moved files (history preserved via `git mv`)
- [ ] `knowledge-base/project/components/knowledge-base.md` directory tree updated

## Test Scenarios

- Given the cleanup is complete, when running `ls knowledge-base/project/`, then only `constitution.md`, `README.md`, and `components/` are listed
- Given the cleanup is complete, when running `ls knowledge-base/features/`, then the command fails (directory does not exist)
- Given the cleanup is complete, when running `ls knowledge-base/learnings/bug-fixes/`, then category files from the old `project/learnings/bug-fixes/` are present
- Given the cleanup is complete, when the learnings-researcher agent searches `knowledge-base/learnings/implementation-patterns/`, then it finds the pattern files that were previously under `project/learnings/implementation-patterns/`
- Given the cleanup is complete, when running `ls knowledge-base/specs/feat-plausible-goals/`, then spec files from both the old `project/` and root locations are merged
- Given the cleanup is complete, when the archive-kb.sh script runs, then it discovers artifacts at the canonical root-level paths (no change from current behavior)
- Given the cleanup is complete, when checking `git log --follow` on a moved file, then the pre-move commit history is visible

## Rollback Plan

`git revert HEAD` cleanly undoes all `git mv` operations, restoring the split state. No runtime behavior changes -- skills already point to root-level paths.

## Dependencies & Risks

### Risk: Large diff

Moving 380+ files produces a large diff. Using `git mv` ensures git tracks renames, but the PR diff will be large. Mitigate by keeping move and update commits separate for reviewability.

### Risk: Concurrent worktree conflicts

Other active worktrees (`feat-653-growth-audit-p1`, `feat-ralph-loop-session-scope`, `feat-web-platform-ux`) may reference files in `knowledge-base/project/`. After this PR merges, those branches will need to merge origin/main and resolve any path conflicts. The pre-merge-rebase hook enforces this.

### Dependency: No skill changes needed

Skills already reference canonical root-level paths after #606. This cleanup only moves physical files -- no code changes required in plugins/.

## Semver Intent

`semver:patch` -- internal file consolidation, no user-facing behavior change.

## References

- KB restructure sequence: #566, #570, #573, #581, #602, #606
- Issue #568 (group under features/ -- shipped then reversed)
- Issue #569/#570 (overview/ to project/ rename)
- Issue #604 (stale reference cleanup in SKILL.md files)
- Learning: `knowledge-base/learnings/2026-03-13-archive-kb-stale-path-resolution.md`
- Constitution: `knowledge-base/project/constitution.md` (lines 85-86 on `git mv` requirements)
