---
title: "fix: archive-kb.sh searches stale knowledge-base/project/ paths"
branch: feat/fix-archive-kb-paths
issue: "#600"
plan: knowledge-base/plans/2026-03-13-fix-archive-kb-stale-paths-plan.md
---

# Tasks: fix archive-kb.sh stale paths

## Phase 1: Core Fix

- [ ] 1.1 Update `discover_artifacts()` in `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`
  - [ ] 1.1.1 Add current brainstorm path: `knowledge-base/brainstorms/`
  - [ ] 1.1.2 Add current plans path: `knowledge-base/plans/`
  - [ ] 1.1.3 Add current specs path: `knowledge-base/specs/`
  - [ ] 1.1.4 Add alternate specs path: `knowledge-base/features/specs/`
  - [ ] 1.1.5 Keep legacy paths: `knowledge-base/project/{brainstorms,plans,specs}/`

## Phase 2: Documentation

- [ ] 2.1 Update `plugins/soleur/skills/archive-kb/SKILL.md`
  - [ ] 2.1.1 Update "What It Archives" table to list all searched directories
  - [ ] 2.1.2 Note that both current and legacy paths are searched

## Phase 3: Verification

- [ ] 3.1 Run `archive-kb.sh --dry-run` against a slug with artifacts in current paths
- [ ] 3.2 Verify artifacts in legacy `knowledge-base/project/` paths are still discovered
- [ ] 3.3 Verify `archive/` subdirectories are excluded from all paths
