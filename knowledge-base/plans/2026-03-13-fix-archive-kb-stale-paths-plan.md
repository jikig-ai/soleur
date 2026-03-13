---
title: "fix: archive-kb.sh searches stale knowledge-base/project/ paths"
type: fix
date: 2026-03-13
issue: "#600"
---

# fix: archive-kb.sh searches stale knowledge-base/project/ paths

## Overview

`archive-kb.sh` hardcodes legacy `knowledge-base/project/{brainstorms,plans,specs}` paths in its `discover_artifacts()` function. After the KB restructure (#566, #568), artifacts now live at `knowledge-base/brainstorms/`, `knowledge-base/plans/`, `knowledge-base/specs/`, and `knowledge-base/features/specs/`. The script reports "No artifacts found" even when artifacts exist at the current paths.

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
- `knowledge-base/brainstorms/` (new primary)
- `knowledge-base/plans/` (new primary)
- `knowledge-base/specs/feat-<slug>/` (new primary)
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

### Update `SKILL.md` documentation

Update the "What It Archives" table in `plugins/soleur/skills/archive-kb/SKILL.md` to reflect all searched directories instead of only the legacy paths.

## Acceptance Criteria

- [ ] `archive-kb.sh` discovers artifacts in `knowledge-base/brainstorms/` (current path)
- [ ] `archive-kb.sh` discovers artifacts in `knowledge-base/plans/` (current path)
- [ ] `archive-kb.sh` discovers artifacts in `knowledge-base/specs/feat-<slug>/` (current path)
- [ ] `archive-kb.sh` discovers artifacts in `knowledge-base/features/specs/feat-<slug>/` (alternate current path)
- [ ] `archive-kb.sh` still discovers artifacts in `knowledge-base/project/brainstorms/` (legacy path)
- [ ] `archive-kb.sh` still discovers artifacts in `knowledge-base/project/plans/` (legacy path)
- [ ] `archive-kb.sh` still discovers artifacts in `knowledge-base/project/specs/feat-<slug>/` (legacy path)
- [ ] `archive/` subdirectories are excluded from all paths
- [ ] `--dry-run` flag works correctly with new paths
- [ ] `SKILL.md` documentation reflects the updated search paths

## Test Scenarios

- Given artifacts exist only in `knowledge-base/brainstorms/`, when `archive-kb.sh` runs, then they are discovered and archived
- Given artifacts exist only in `knowledge-base/project/brainstorms/` (legacy), when `archive-kb.sh` runs, then they are still discovered and archived
- Given artifacts exist in both current and legacy paths, when `archive-kb.sh` runs, then all are discovered (no duplicates since paths differ)
- Given artifacts exist in `knowledge-base/features/specs/feat-<slug>/`, when `archive-kb.sh` runs, then the spec directory is discovered
- Given no artifacts exist for the slug, when `archive-kb.sh` runs, then "No artifacts found" is printed and exit code is 0
- Given `--dry-run` is passed with artifacts in current paths, when `archive-kb.sh` runs, then the correct archive destinations are displayed without executing

## Context

### Related Learnings

- `knowledge-base/project/learnings/2026-03-13-stale-cross-references-after-kb-restructuring.md`: After #566 restructured KB paths, stale references remained. The key insight: use `grep -r` to find all references to old paths BEFORE merging restructuring PRs.
- `knowledge-base/project/learnings/workflow-issues/2026-03-13-kb-restructure-grep-scope-must-include-product-docs.md`: The grep scope for path restructures must include ALL of `knowledge-base/`, not just "executable code."

### Wider Stale Path Issue

The grep search revealed **60+ references** to `knowledge-base/project/` paths across skill SKILL.md files (plan, work, brainstorm, compound, compound-capture, ship, merge-pr, spec-templates, deepen-plan, one-shot, archive-kb) and `worktree-manager.sh`. These are all potentially stale references from the same KB restructure. However, issue #600 is scoped specifically to `archive-kb.sh` -- the script that fails silently because it's bash (not an LLM skill that can adapt). Fixing the broader SKILL.md references should be tracked as a separate issue.

### Files to Modify

1. `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` -- update `discover_artifacts()` function
2. `plugins/soleur/skills/archive-kb/SKILL.md` -- update documentation table

## References

- Issue: #600
- KB restructure PRs: #566, #568
- Stale reference fix PR: #569
- Related learning: `2026-03-13-stale-cross-references-after-kb-restructuring.md`
