# Spec: Docs Cleanup and Knowledge-Base Migration

**Feature:** feat-docs-cleanup
**Created:** 2026-02-06
**Status:** Ready for Implementation

## Problem Statement

Following the implementation of the spec-driven workflow (issues #3 and #4), documentation is scattered across `/docs/` subdirectories while the new `/knowledge-base/` structure sits mostly empty. Additionally, the `/openspec/` directory contains unused scaffolding that adds confusion.

## Goals

1. Consolidate all project documentation into the `knowledge-base/` structure
2. Clean up the unused `openspec/` directory by integrating its rules
3. Document learnings from the spec-driven workflow implementation
4. Maintain the documentation site (docs/pages/, css/, js/)

## Non-Goals

- Changing the documentation site content or structure
- Creating new documentation beyond the learnings document

## Related

- **GitHub Issue:** #5
- **Branch:** feat-docs-cleanup
- **Brainstorm:** docs/brainstorms/2026-02-06-docs-cleanup-and-archive-brainstorm.md

## Functional Requirements

### FR1: Plans Migration
- Convert `docs/plans/2026-02-06-feat-spec-workflow-foundation-plan.md` to `knowledge-base/specs/feat-spec-workflow-foundation/spec.md`
- Convert `docs/plans/2026-02-06-feat-command-integration-plan.md` to `knowledge-base/specs/feat-command-integration/spec.md`
- Move `docs/plans/archive/*.md` to `knowledge-base/specs/archive/`
- Delete `docs/plans/` directory after migration

### FR2: External Specs Migration
- Create `knowledge-base/specs/external/` directory
- Move `docs/specs/claude-code.md`, `codex.md`, `opencode.md` to external/
- Delete `docs/specs/` directory after migration

### FR3: Solutions Migration
- Move `docs/solutions/plugin-versioning-requirements.md` to `knowledge-base/learnings/`
- Delete `docs/solutions/` directory after migration

### FR4: Brainstorms Migration
- Create `knowledge-base/brainstorms/` directory
- Move `docs/brainstorms/2026-02-05-unified-spec-workflow-brainstorm.md`
- Move `docs/brainstorms/2026-02-06-docs-cleanup-and-archive-brainstorm.md`
- Delete `docs/brainstorms/` directory after migration

### FR5: OpenSpec Integration
- Extract rules from `openspec/config.yaml`
- Integrate proposal, spec, design, and task rules into `knowledge-base/constitution.md`
- Delete entire `openspec/` directory

### FR6: Learnings Documentation
- Create `knowledge-base/learnings/2026-02-06-spec-workflow-implementation.md`
- Document key learnings from implementing issues #3 and #4

### FR7: Workflow Command Enhancement
- Update `plugins/soleur/commands/soleur/brainstorm.md` to include GitHub issue creation step
- Add issue creation after worktree creation in Phase 3.5
- Update output summary to show issue number and branch

## Technical Requirements

### TR1: Preserve Git History
- Use `git mv` for all file moves to preserve history

### TR2: Update References
- Check CLAUDE.md and other files for references to moved paths
- Update any broken references

### TR3: Verify Documentation Site
- Ensure `docs/pages/`, `docs/css/`, `docs/js/` remain intact
- Verify site still builds/serves correctly after cleanup

## Success Criteria

- [ ] All files migrated to knowledge-base structure
- [ ] openspec/ directory removed
- [ ] docs/ only contains documentation site files (pages/, css/, js/)
- [ ] No broken references in CLAUDE.md or other docs
- [ ] Learnings document created with implementation insights
- [ ] Constitution.md updated with openspec rules
- [ ] brainstorm.md command updated with GitHub issue creation step
