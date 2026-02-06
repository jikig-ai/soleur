# Tasks: Docs Cleanup and Knowledge-Base Migration

**Feature:** feat-docs-cleanup
**Created:** 2026-02-06
**Issue:** #5

## Phase 1: Setup

- [x] **1.1** Create `knowledge-base/specs/external/` directory
- [x] **1.2** Create `knowledge-base/specs/archive/` directory
- [x] **1.3** Create `knowledge-base/brainstorms/` directory
- [x] **1.4** Create `knowledge-base/specs/feat-spec-workflow-foundation/` directory
- [x] **1.5** Create `knowledge-base/specs/feat-command-integration/` directory

## Phase 2: File Migrations

### 2.1 Plans Migration (FR1)

- [x] **2.1.1** Convert `docs/plans/2026-02-06-feat-spec-workflow-foundation-plan.md` to `knowledge-base/specs/feat-spec-workflow-foundation/spec.md`
  - Use `git mv` to preserve history
  - Update frontmatter to spec format
- [x] **2.1.2** Convert `docs/plans/2026-02-06-feat-command-integration-plan.md` to `knowledge-base/specs/feat-command-integration/spec.md`
  - Use `git mv` to preserve history
  - Update frontmatter to spec format
- [x] **2.1.3** Move archived plans to `knowledge-base/specs/archive/`
  - `git mv docs/plans/archive/2026-02-05-feat-command-integration-plan.md knowledge-base/specs/archive/`
  - `git mv docs/plans/archive/2026-02-05-feat-knowledge-base-foundation-plan.md knowledge-base/specs/archive/`
  - `git mv docs/plans/archive/2026-02-05-feat-knowledge-layer-compounding-plan.md knowledge-base/specs/archive/`
  - `git mv docs/plans/archive/2026-02-05-feat-spec-layer-artifacts-plan.md knowledge-base/specs/archive/`
  - `git mv docs/plans/archive/2026-02-05-feat-worktree-layer-enhancements-plan.md knowledge-base/specs/archive/`

### 2.2 External Specs Migration (FR2)

- [x] **2.2.1** Move external specs to `knowledge-base/specs/external/`
  - `git mv docs/specs/claude-code.md knowledge-base/specs/external/`
  - `git mv docs/specs/codex.md knowledge-base/specs/external/`
  - `git mv docs/specs/opencode.md knowledge-base/specs/external/`

### 2.3 Solutions Migration (FR3)

- [x] **2.3.1** Move solutions to `knowledge-base/learnings/`
  - `git mv docs/solutions/plugin-versioning-requirements.md knowledge-base/learnings/`

### 2.4 Brainstorms Migration (FR4)

- [x] **2.4.1** Move brainstorm documents to `knowledge-base/brainstorms/`
  - `git mv docs/brainstorms/2026-02-05-unified-spec-workflow-brainstorm.md knowledge-base/brainstorms/`
  - `git mv docs/brainstorms/2026-02-06-docs-cleanup-and-archive-brainstorm.md knowledge-base/brainstorms/`

## Phase 3: Content Updates

### 3.1 OpenSpec Integration (FR5)

- [x] **3.1.1** Read `openspec/config.yaml` and extract rules
- [x] **3.1.2** Update `knowledge-base/constitution.md` with extracted rules:
  - Add Proposal section with: rollback plan, affected teams, Non-goals requirement
  - Add Spec section with: Given/When/Then format
  - Add Design section with: sequence diagrams for complex flows
  - Add Task section with: max 2 hour chunks

### 3.2 Learnings Documentation (FR6)

- [x] **3.2.1** Create `knowledge-base/learnings/2026-02-06-spec-workflow-implementation.md`
  - Document: 8 domains -> 3 domains simplification
  - Document: Human-in-the-loop v1 decision
  - Document: Fall-back patterns for backward compatibility
  - Document: Convention over configuration (branch names -> spec directories)
  - Document: Skill-based architecture for reuse

### 3.3 Command Enhancement (FR7) - DONE

- [x] **3.3.1** Update `plugins/soleur/commands/soleur/brainstorm.md` with GitHub issue creation step
- [x] **3.3.2** Update `plugins/soleur/commands/soleur/brainstorm.md` with worktree switch step
- [x] **3.3.3** Update output summary to show issue number and branch

## Phase 4: Reference Updates (TR2)

### 4.1 Command Files

- [ ] **4.1.1** Update `plugins/soleur/commands/soleur/brainstorm.md`
  - Change `docs/brainstorms/` references to `knowledge-base/brainstorms/`
- [ ] **4.1.2** Update `plugins/soleur/commands/soleur/plan.md`
  - Change `docs/brainstorms/` references to `knowledge-base/brainstorms/`
  - Change `docs/solutions/` references to `knowledge-base/learnings/`
  - Change `docs/plans/` references to `knowledge-base/specs/`
- [ ] **4.1.3** Update `plugins/soleur/commands/soleur/compound.md`
  - Change `docs/solutions/` references to `knowledge-base/learnings/`
- [ ] **4.1.4** Update `plugins/soleur/commands/deepen-plan.md`
  - Verify and update any docs/ references

### 4.2 Skill Files

- [ ] **4.2.1** Update `plugins/soleur/skills/compound-docs/SKILL.md`
  - Change `docs/solutions/` references to `knowledge-base/learnings/`
- [ ] **4.2.2** Update `plugins/soleur/skills/compound-docs/references/yaml-schema.md`
  - Update all category->path mappings from `docs/solutions/` to `knowledge-base/learnings/`
- [ ] **4.2.3** Update `plugins/soleur/skills/compound-docs/assets/critical-pattern-template.md`
  - Change `docs/solutions/patterns/` to `knowledge-base/learnings/patterns/`
- [ ] **4.2.4** Update `plugins/soleur/skills/compound-docs/assets/resolution-template.md`
  - Change `docs/solutions/` references to `knowledge-base/learnings/`
- [ ] **4.2.5** Update `plugins/soleur/skills/brainstorming/SKILL.md`
  - Change brainstorm output path references

### 4.3 Plugin Documentation

- [ ] **4.3.1** Update `plugins/soleur/AGENTS.md`
  - Change `docs/solutions/plugin-versioning-requirements.md` to `knowledge-base/learnings/plugin-versioning-requirements.md`

## Phase 5: Cleanup

### 5.1 Delete Empty Directories

- [ ] **5.1.1** Delete `docs/plans/archive/` (after verifying empty)
- [ ] **5.1.2** Delete `docs/plans/` (after verifying empty)
- [ ] **5.1.3** Delete `docs/specs/` (after verifying empty)
- [ ] **5.1.4** Delete `docs/solutions/` (after verifying empty)
- [ ] **5.1.5** Delete `docs/brainstorms/` (after verifying empty)
- [ ] **5.1.6** Delete `openspec/` directory entirely

### 5.2 Verification (TR3)

- [ ] **5.2.1** Verify `docs/` only contains site files (pages/, css/, js/, index.html)
- [ ] **5.2.2** Run `grep -r "docs/plans\|docs/specs\|docs/solutions\|docs/brainstorms" plugins/` to find any missed references
- [ ] **5.2.3** Verify documentation site still loads correctly

## Phase 6: Finalization

- [ ] **6.1** Run `bun test` to verify no breaking changes
- [ ] **6.2** Commit all changes with descriptive message
- [ ] **6.3** Push branch and create PR

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Phase 1: Setup | 5 | Pending |
| Phase 2: Migrations | 9 | Pending |
| Phase 3: Content | 5 | 3 Done |
| Phase 4: References | 10 | Pending |
| Phase 5: Cleanup | 9 | Pending |
| Phase 6: Final | 3 | Pending |
| **Total** | **41** | **3 Done** |
