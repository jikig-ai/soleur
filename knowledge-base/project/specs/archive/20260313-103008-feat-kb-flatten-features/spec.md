# Spec: Merge knowledge-base/features/ into knowledge-base/project/

**Status:** Draft
**Branch:** feat/kb-flatten-features

## Problem Statement

The `knowledge-base/` taxonomy uses top-level directories for domains (engineering, marketing, etc.) but `features/` breaks this principle — it's an artifact category, not a domain. This creates an inconsistency and an extra level of nesting.

## Goals

- G1: Merge `features/{brainstorms,learnings,plans,specs}` into `project/`
- G2: Delete stale top-level `knowledge-base/project/specs/` leftover
- G3: Update all path references across skills, scripts, and agents

## Non-Goals

- Restructuring domain directories (engineering, marketing, etc.)
- Renaming `project/` to something else
- Changing the archive structure within subdirectories

## Functional Requirements

- FR1: `git mv` all contents of `features/` subdirs into `project/` (preserving git history)
- FR2: Remove empty `features/` directory
- FR3: Delete stale `knowledge-base/project/specs/` directory
- FR4: Update all path references in skill SKILL.md files (12 files)
- FR5: Update hardcoded paths in shell scripts (worktree-manager.sh, archive-kb.sh)
- FR6: Update path references in agent files (cpo.md)

## Technical Requirements

- TR1: Use `git mv` for all moves to preserve history
- TR2: Grep-verify zero remaining `knowledge-base/features/` references after update
- TR3: Ensure worktree-manager.sh creates spec dirs at new path
- TR4: Ensure archive-kb.sh archives to new paths
- TR5: Ensure compound/compound-capture skills write learnings to new path

## Files to Modify

### Shell Scripts
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`

### Skills (SKILL.md)
- `plugins/soleur/skills/work/SKILL.md`
- `plugins/soleur/skills/plan/SKILL.md`
- `plugins/soleur/skills/compound/SKILL.md`
- `plugins/soleur/skills/compound-capture/SKILL.md`
- `plugins/soleur/skills/spec-templates/SKILL.md`
- `plugins/soleur/skills/archive-kb/SKILL.md`
- `plugins/soleur/skills/brainstorm/SKILL.md`
- `plugins/soleur/skills/brainstorm-techniques/SKILL.md`
- `plugins/soleur/skills/deepen-plan/SKILL.md`
- `plugins/soleur/skills/merge-pr/SKILL.md`
- `plugins/soleur/skills/one-shot/SKILL.md`
- `plugins/soleur/skills/ship/SKILL.md`

### Agents
- `plugins/soleur/agents/product/cpo.md`

### Directories to Move
- `knowledge-base/features/brainstorms/` → `knowledge-base/project/brainstorms/`
- `knowledge-base/features/learnings/` → `knowledge-base/project/learnings/`
- `knowledge-base/features/plans/` → `knowledge-base/project/plans/`
- `knowledge-base/features/specs/` → `knowledge-base/project/specs/`

### Directories to Delete
- `knowledge-base/features/` (after moves)
- `knowledge-base/project/specs/` (stale leftover)
