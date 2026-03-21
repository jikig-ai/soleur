---
title: "fix: archive-kb.sh searches stale knowledge-base/project/ paths"
type: fix
date: 2026-03-13
issue: "#600"
deepened: 2026-03-13
---

# fix: archive-kb.sh searches stale knowledge-base/project/ paths

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 4 (Proposed Solution, Acceptance Criteria, Test Scenarios, Context)

### Key Improvements

1. Identified `worktree-manager.sh` as a co-affected file with the same stale paths -- must be fixed in this PR to prevent the same silent failure during `cleanup-merged`
2. Verified `archive_artifact()` and `print_archive_path()` use `dirname`-based archive path computation, so they work correctly with any source directory without modification
3. Added edge case analysis: `nullglob` handles nonexistent directories gracefully, and empty `artifacts` array produces no output (handled by caller's `[[ -n "$line" ]]` guard)

### New Considerations Discovered

- `worktree-manager.sh` lines 426-427 hardcode `knowledge-base/project/specs/` for spec dir creation and archival -- same stale path pattern
- `worktree-manager.sh` lines 465-466 hardcode `knowledge-base/project/brainstorms` and `knowledge-base/project/plans` in `archive_kb_files` calls
- The `worktree-manager.sh` uses `mv` (not `git mv`) for archiving, so it's a different code path but same stale directory problem
- Shell defensive patterns learning recommends these are mechanical fixes -- no judgment calls needed

## Overview

`archive-kb.sh` hardcodes legacy `knowledge-base/project/{brainstorms,plans,specs}` paths in its `discover_artifacts()` function. After the KB restructure (#566, #568), artifacts now live at `knowledge-base/project/brainstorms/`, `knowledge-base/project/plans/`, `knowledge-base/project/specs/`, and `knowledge-base/features/specs/`. The script reports "No artifacts found" even when artifacts exist at the current paths.

## Problem Statement

During `soleur:compound` on `feat-utm-conventions`, the archival step ran `archive-kb.sh` which returned "No artifacts found for slug 'utm-conventions'" despite 4 artifacts existing at the correct (post-restructure) paths. The root cause is three hardcoded path prefixes in `discover_artifacts()`:

```bash
# Line 98: searches knowledge-base/project/brainstorms/ (stale)
for f in knowledge-base/project/brainstorms/*"${slug}"*; do

# Line 103: searches knowledge-base/project/plans/ (stale)
for f in knowledge-base/project/plans/*"${slug}"*; do

# Line 108: checks knowledge-base/project/specs/feat-<slug> (stale)
if [[ -d "knowledge-base/project/specs/feat-${slug}" ]]; then
```

The actual artifact locations are now:

- `knowledge-base/project/brainstorms/` (new primary)
- `knowledge-base/project/plans/` (new primary)
- `knowledge-base/project/specs/feat-<slug>/` (new primary)
- `knowledge-base/features/specs/feat-<slug>/` (alternate new location)
- `knowledge-base/project/brainstorms/` (legacy, still has content)
- `knowledge-base/project/plans/` (legacy, still has content)
- `knowledge-base/project/specs/feat-<slug>/` (legacy, still has content)

## Proposed Solution

Update `discover_artifacts()` to search **both legacy and current paths**. This is safer than removing legacy paths because `knowledge-base/project/` still contains real artifacts that haven't been migrated.

### Changes to `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`

**Update `discover_artifacts()` (lines 90-115):**

Replace the three single-path glob loops with loops over arrays of candidate directories:

```bash
discover_artifacts() {
  local slug="$1"
  local artifacts=()

  shopt -s nullglob

  # Brainstorms: search current and legacy paths
  local brainstorm_dirs=(
    "knowledge-base/brainstorms"
    "knowledge-base/project/brainstorms"
  )
  for dir in "${brainstorm_dirs[@]}"; do
    for f in "$dir"/*"${slug}"*; do
      [[ -f "$f" && "$f" != */archive/* ]] && artifacts+=("$f")
    done
  done

  # Plans: search current and legacy paths
  local plan_dirs=(
    "knowledge-base/plans"
    "knowledge-base/project/plans"
  )
  for dir in "${plan_dirs[@]}"; do
    for f in "$dir"/*"${slug}"*; do
      [[ -f "$f" && "$f" != */archive/* ]] && artifacts+=("$f")
    done
  done

  # Specs: check current and legacy paths for exact directory match
  local spec_dirs=(
    "knowledge-base/specs"
    "knowledge-base/features/specs"
    "knowledge-base/project/specs"
  )
  for dir in "${spec_dirs[@]}"; do
    if [[ -d "$dir/feat-${slug}" ]]; then
      artifacts+=("$dir/feat-${slug}")
    fi
  done

  shopt -u nullglob

  printf '%s\n' "${artifacts[@]}"
}
```

### Research Insights for `archive-kb.sh`

**Correctness verification:**

- The `archive_artifact()` function (lines 154-167) computes the archive destination using `dirname "$artifact"`, so it places each artifact's archive in the correct subdirectory (`knowledge-base/project/brainstorms/archive/`, `knowledge-base/project/brainstorms/archive/`, etc.) regardless of which base path the artifact came from. No changes needed to `archive_artifact()` or `print_archive_path()`.
- The `nullglob` shell option ensures that globbing against a nonexistent directory (e.g., if `knowledge-base/project/brainstorms/` doesn't exist yet) expands to nothing rather than a literal glob string. This means the dir arrays are safe without explicit `-d` guards on each entry.
- The `printf '%s\n' "${artifacts[@]}"` with an empty array prints nothing (not even a newline in bash 4+), and the caller's `[[ -n "$line" ]]` guard handles empty lines. No risk of phantom artifacts.

**Ordering consideration:**
Current paths are listed before legacy paths in each array. This means if an artifact exists at both locations (unlikely but possible during migration), both will be discovered and archived. This is the correct behavior -- archiving a stale copy alongside the current copy is better than silently leaving it behind.

### Changes to `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

The `worktree-manager.sh` has the same stale paths in three locations and must be fixed in this PR:

**1. `create_for_feature()` spec dir creation (line 152):**

```bash
# Current (stale):
local spec_dir="$GIT_ROOT/knowledge-base/project/specs/$branch_name"

# Fixed:
local spec_dir="$GIT_ROOT/knowledge-base/project/specs/$branch_name"
```

**2. `cleanup_merged_worktrees()` spec dir archival (lines 426-427):**

```bash
# Current (stale):
local spec_dir="$GIT_ROOT/knowledge-base/project/specs/$safe_branch"
local archive_dir="$GIT_ROOT/knowledge-base/project/specs/archive"

# Fixed -- search all spec locations:
local spec_dirs=(
  "$GIT_ROOT/knowledge-base/project/specs/$safe_branch"
  "$GIT_ROOT/knowledge-base/features/specs/$safe_branch"
  "$GIT_ROOT/knowledge-base/project/specs/$safe_branch"
)
local archive_dir
for candidate in "${spec_dirs[@]}"; do
  if [[ -d "$candidate" ]]; then
    archive_dir="$(dirname "$candidate")/archive"
    # ... archive logic
  fi
done
```

**3. `cleanup_merged_worktrees()` brainstorm/plan archival (lines 465-466):**

```bash
# Current (stale):
archive_kb_files "$GIT_ROOT/knowledge-base/project/brainstorms" "$feature_slug" "brainstorm" "$verbose"
archive_kb_files "$GIT_ROOT/knowledge-base/project/plans" "$feature_slug" "plan" "$verbose"

# Fixed -- search all locations:
archive_kb_files "$GIT_ROOT/knowledge-base/brainstorms" "$feature_slug" "brainstorm" "$verbose"
archive_kb_files "$GIT_ROOT/knowledge-base/project/brainstorms" "$feature_slug" "brainstorm" "$verbose"
archive_kb_files "$GIT_ROOT/knowledge-base/plans" "$feature_slug" "plan" "$verbose"
archive_kb_files "$GIT_ROOT/knowledge-base/project/plans" "$feature_slug" "plan" "$verbose"
```

Note: `archive_kb_files()` already has `[[ -d "$dir" ]] || return 0` as its first line (line 367), so calling it with a nonexistent directory is safe.

**4. Display message (line 194):**

```bash
# Current (stale):
echo -e "  2. Create spec: ${BLUE}knowledge-base/project/specs/$branch_name/spec.md${NC}"

# Fixed:
echo -e "  2. Create spec: ${BLUE}knowledge-base/project/specs/$branch_name/spec.md${NC}"
```

### Update `SKILL.md` documentation

Update the "What It Archives" table in `plugins/soleur/skills/archive-kb/SKILL.md` to reflect all searched directories instead of only the legacy paths.

## Acceptance Criteria

### archive-kb.sh

- [x] `archive-kb.sh` discovers artifacts in `knowledge-base/project/brainstorms/` (current path)
- [x] `archive-kb.sh` discovers artifacts in `knowledge-base/project/plans/` (current path)
- [x] `archive-kb.sh` discovers artifacts in `knowledge-base/project/specs/feat-<slug>/` (current path)
- [x] `archive-kb.sh` discovers artifacts in `knowledge-base/features/specs/feat-<slug>/` (alternate current path)
- [x] `archive-kb.sh` still discovers artifacts in `knowledge-base/project/brainstorms/` (legacy path)
- [x] `archive-kb.sh` still discovers artifacts in `knowledge-base/project/plans/` (legacy path)
- [x] `archive-kb.sh` still discovers artifacts in `knowledge-base/project/specs/feat-<slug>/` (legacy path)
- [x] `archive/` subdirectories are excluded from all paths
- [x] `--dry-run` flag works correctly with new paths
- [x] `SKILL.md` documentation reflects the updated search paths

### worktree-manager.sh

- [x] `create_for_feature()` creates spec dirs at `knowledge-base/project/specs/` (not `knowledge-base/project/specs/`)
- [x] `cleanup_merged_worktrees()` archives specs from all three spec locations
- [x] `cleanup_merged_worktrees()` archives brainstorms from both current and legacy paths
- [x] `cleanup_merged_worktrees()` archives plans from both current and legacy paths
- [x] Display message in `create_for_feature()` shows correct current path

## Test Scenarios

### archive-kb.sh

- Given artifacts exist only in `knowledge-base/project/brainstorms/`, when `archive-kb.sh` runs, then they are discovered and archived to `knowledge-base/project/brainstorms/archive/`
- Given artifacts exist only in `knowledge-base/project/brainstorms/` (legacy), when `archive-kb.sh` runs, then they are still discovered and archived to `knowledge-base/project/brainstorms/archive/`
- Given artifacts exist in both current and legacy paths, when `archive-kb.sh` runs, then all are discovered (no duplicates since paths differ)
- Given artifacts exist in `knowledge-base/features/specs/feat-<slug>/`, when `archive-kb.sh` runs, then the spec directory is discovered and archived to `knowledge-base/features/specs/archive/`
- Given artifacts exist in `knowledge-base/project/specs/feat-<slug>/`, when `archive-kb.sh` runs, then the spec directory is discovered and archived to `knowledge-base/project/specs/archive/`
- Given no artifacts exist for the slug, when `archive-kb.sh` runs, then "No artifacts found" is printed and exit code is 0
- Given `--dry-run` is passed with artifacts in current paths, when `archive-kb.sh` runs, then the correct archive destinations are displayed without executing
- Given a directory in the search list does not exist (e.g., `knowledge-base/project/brainstorms/` missing), when `archive-kb.sh` runs, then no error is raised (nullglob handles gracefully)

### worktree-manager.sh

- Given a merged branch has specs at `knowledge-base/project/specs/feat-<slug>/`, when `cleanup-merged` runs, then the spec dir is archived
- Given a merged branch has specs at `knowledge-base/project/specs/feat-<slug>/` (legacy), when `cleanup-merged` runs, then the spec dir is still archived
- Given a merged branch has brainstorms at `knowledge-base/project/brainstorms/`, when `cleanup-merged` runs, then they are archived
- Given `create_for_feature` is called, then the spec dir is created at `knowledge-base/project/specs/feat-<name>/` (not the legacy path)

## Context

### Related Learnings

- `knowledge-base/project/learnings/2026-03-13-stale-cross-references-after-kb-restructuring.md`: After #566 restructured KB paths, stale references remained. The key insight: use `grep -r` to find all references to old paths BEFORE merging restructuring PRs.
- `knowledge-base/project/learnings/workflow-issues/2026-03-13-kb-restructure-grep-scope-must-include-product-docs.md`: The grep scope for path restructures must include ALL of `knowledge-base/`, not just "executable code."

### Wider Stale Path Issue

The grep search revealed **60+ references** to `knowledge-base/project/` paths across skill SKILL.md files (plan, work, brainstorm, compound, compound-capture, ship, merge-pr, spec-templates, deepen-plan, one-shot, archive-kb) and `worktree-manager.sh`. The SKILL.md references affect LLM skill instructions, which can adapt because agents read the actual filesystem. However, **two bash scripts** cannot adapt and will silently fail:

1. `archive-kb.sh` -- the primary target of this fix (issue #600)
2. `worktree-manager.sh` -- uses its own `archive_kb_files()` function with the same stale paths, affecting `cleanup-merged` workflow

Both scripts must be fixed in this PR. The broader SKILL.md reference cleanup should be tracked as a separate issue.

### Files to Modify

1. `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` -- update `discover_artifacts()` function (lines 90-115)
2. `plugins/soleur/skills/archive-kb/SKILL.md` -- update documentation table
3. `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- update `create_for_feature()` spec dir path (line 152), `cleanup_merged_worktrees()` spec/brainstorm/plan archival paths (lines 426-427, 465-466), and display message (line 194)

### Scope Boundary

This PR fixes only the two bash scripts that silently fail. It does NOT update SKILL.md files for other skills (plan, work, brainstorm, compound, etc.) because:

- LLM agents reading those SKILL.md files can see the actual filesystem and adapt
- Updating 10+ SKILL.md files increases PR scope and review burden
- A separate issue should track the SKILL.md reference cleanup as a documentation chore

## References

- Issue: #600
- KB restructure PRs: #566, #568
- Stale reference fix PR: #569
- Related learning: `2026-03-13-stale-cross-references-after-kb-restructuring.md`
