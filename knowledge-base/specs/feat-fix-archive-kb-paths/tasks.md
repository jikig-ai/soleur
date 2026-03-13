---
title: "fix: archive-kb.sh searches stale knowledge-base/project/ paths"
branch: feat/fix-archive-kb-paths
issue: "#600"
plan: knowledge-base/plans/2026-03-13-fix-archive-kb-stale-paths-plan.md
---

# Tasks: fix archive-kb.sh stale paths

## Phase 1: Core Fix -- archive-kb.sh

- [x] 1.1 Update `discover_artifacts()` in `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`
  - [x] 1.1.1 Add current brainstorm path: `knowledge-base/brainstorms/`
  - [x] 1.1.2 Add current plans path: `knowledge-base/plans/`
  - [x] 1.1.3 Add current specs path: `knowledge-base/specs/`
  - [x] 1.1.4 Add alternate specs path: `knowledge-base/features/specs/`
  - [x] 1.1.5 Keep legacy paths: `knowledge-base/project/{brainstorms,plans,specs}/`

## Phase 2: Core Fix -- worktree-manager.sh

- [x] 2.1 Update `create_for_feature()` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - [x] 2.1.1 Change spec_dir from `knowledge-base/project/specs/` to `knowledge-base/specs/` (line 152)
  - [x] 2.1.2 Update display message to show current path (line 194)
- [x] 2.2 Update `cleanup_merged_worktrees()` spec archival (lines 426-427)
  - [x] 2.2.1 Search all three spec locations: `knowledge-base/specs/`, `knowledge-base/features/specs/`, `knowledge-base/project/specs/`
- [x] 2.3 Update `cleanup_merged_worktrees()` brainstorm/plan archival (lines 465-466)
  - [x] 2.3.1 Add current brainstorm path: `knowledge-base/brainstorms`
  - [x] 2.3.2 Add current plans path: `knowledge-base/plans`
  - [x] 2.3.3 Keep legacy paths for both

## Phase 3: Documentation

- [x] 3.1 Update `plugins/soleur/skills/archive-kb/SKILL.md`
  - [x] 3.1.1 Update "What It Archives" table to list all searched directories
  - [x] 3.1.2 Note that both current and legacy paths are searched

## Phase 4: Verification

- [x] 4.1 Run `archive-kb.sh --dry-run` against a slug with artifacts in current paths
- [x] 4.2 Verify artifacts in legacy `knowledge-base/project/` paths are still discovered
- [x] 4.3 Verify `archive/` subdirectories are excluded from all paths
- [x] 4.4 Verify `worktree-manager.sh` create_for_feature creates spec dir at correct path
