---
title: "feat: Spec Layer - Artifacts and Evolution"
type: feat
date: 2026-02-05
layer: spec
priority: 3
dependencies:
  - 2026-02-05-feat-knowledge-base-foundation-plan.md
---

# Spec Layer - Artifacts and Evolution

## Overview

Implement the spec artifact system with two-file approach (spec.md + tasks.md) and spec evolution mechanism that keeps specs in sync with implementation.

## Problem Statement

Current workflow lacks:
- Standardized spec format for features
- Structured task tracking tied to specs
- Mechanism to detect when implementation diverges from spec
- Auto-update capability to keep specs as living documents

## Proposed Solution

### 1. Spec Artifact Format

Two files per feature in `knowledge-base/specs/<feature-name>/`:

**spec.md** - Pure markdown with FR/TR split:
- Context (optional)
- Problem Statement
- Goals / Non-Goals
- Functional Requirements (FR1, FR2, ...)
- Technical Requirements (TR1, TR2, ...)
- Constraints (optional)

**tasks.md** - Grouped phases with hierarchical checkboxes:
- Phase 1: Setup
- Phase 2: Core Implementation
- Phase 3: Testing & Polish

### 2. Spec Templates Skill

Create `plugins/soleur/skills/spec-templates/` with templates for spec.md and tasks.md that commands can use.

### 3. Spec Sync Command

Create `soleur:sync-spec` command that:
- Detects divergence between spec and implementation
- Auto-updates spec to match reality
- Commits changes with descriptive message

### 4. Integration Points

- `soleur:brainstorm` creates spec.md at end
- `soleur:plan` creates tasks.md
- `soleur:compound` checks for divergence and syncs

## Technical Approach

### Phase 1: Spec Templates Skill

**Create:** `plugins/soleur/skills/spec-templates/SKILL.md`

```markdown
---
name: spec-templates
description: Templates for spec.md and tasks.md artifacts
---

# Spec Templates

Provides standardized templates for feature specifications.

## spec.md Template

```markdown
# Feature: {{feature-name}}

## Context
[Optional background information]

## Problem Statement
[What problem are we solving?]

## Goals
- [What we want to achieve]

## Non-Goals
- [What is explicitly out of scope]

## Functional Requirements

### FR1: {{requirement-name}}
[What the system should do - user-facing behavior]

## Technical Requirements

### TR1: {{requirement-name}}
[How it should be built - architecture, performance, security]

## Constraints
[Optional: technical, time, resource constraints]
```

## tasks.md Template

```markdown
# Tasks: {{feature-name}}

## Phase 1: Setup
- [ ] 1.1 Task description

## Phase 2: Core Implementation
- [ ] 2.1 Main task
  - [ ] 2.1.1 Subtask

## Phase 3: Testing & Polish
- [ ] 3.1 Task description
```
```

### Phase 2: Spec Sync Command

**Create:** `plugins/soleur/commands/soleur/sync-spec.md`

```yaml
---
name: sync-spec
description: Sync spec.md with current implementation
argument-hint: "[feature-name]"
---
```

**Behavior:**

1. **Identify feature:** Use current branch name or argument
2. **Load spec:** Read `knowledge-base/specs/<feature>/spec.md`
3. **Analyze implementation:**
   - Scan files changed since spec was created
   - Identify new functions/classes not in spec
   - Detect behavior changes vs spec
4. **Generate diff:**
   - New requirements to add
   - Modified requirements to update
   - Removed requirements to deprecate
5. **Update spec:**
   - Add new FR/TR sections for new functionality
   - Update existing sections for changed behavior
   - Mark removed items as deprecated
6. **Update tasks:**
   - Mark completed tasks based on implementation
   - Add new tasks for discovered work
7. **Commit:**
   - `git commit -m "sync: spec updated to match implementation"`

### Phase 3: Divergence Detection

**Logic for detecting divergence:**

```markdown
## Divergence Types

### New Files/Functions
- Compare files touched in branch vs files mentioned in spec
- New public functions/classes not in spec = divergence

### Changed Behavior
- Compare spec descriptions to implementation
- Agent analyzes if implementation matches spec intent

### Scope Changes
- Features added beyond original spec
- Features removed from original plan
```

**Concrete Detection Heuristics:**

| Signal | Detection Method | Confidence |
|--------|-----------------|------------|
| New exports | `grep -r "export" \| diff` against spec mentions | High |
| New routes | Parse route files, compare to spec endpoints | High |
| New CLI commands | Scan command files not in spec | High |
| New types/interfaces | AST parse public types, compare to spec | Medium |
| Changed signatures | Compare function signatures to spec descriptions | Medium |
| New dependencies | `package.json` diff, check if spec mentions | Low |

**Implementation approach:**

```typescript
// src/divergence/detector.ts
interface DivergenceReport {
  newExports: string[];      // Public APIs not in spec
  newRoutes: string[];       // Endpoints not in spec
  changedSignatures: Array<{ file: string; before: string; after: string }>;
  confidence: "high" | "medium" | "low";
}

function detectDivergence(specPath: string, branchDiff: string): DivergenceReport {
  // 1. Parse spec for mentioned files/functions/routes
  // 2. Parse git diff for actual changes
  // 3. Compare and report gaps
}
```

**Integration in soleur:compound:**

```markdown
### Spec Sync Check

1. Check if spec exists for current feature
2. If yes, analyze implementation vs spec
3. If divergence detected:
   - Show summary of changes
   - Auto-update spec
   - Commit with sync message
4. Report: "Spec synced: +2 FR, ~1 TR modified"
```

## Acceptance Criteria

- [ ] `plugins/soleur/skills/spec-templates/SKILL.md` exists with both templates
- [ ] Templates are pure markdown (no YAML frontmatter in spec.md)
- [ ] spec.md has Context, Problem, Goals, Non-Goals, FR, TR, Constraints sections
- [ ] tasks.md has Phase structure with hierarchical checkboxes
- [ ] `soleur:sync-spec` command exists and can detect divergence
- [ ] `soleur:sync-spec` auto-updates spec with new/changed requirements
- [ ] Spec updates are committed with "sync:" prefix
- [ ] `soleur:compound` checks for divergence and calls sync

## Success Metrics

- Specs stay current with implementation (no stale documentation)
- Git history shows spec evolution alongside code
- Tasks reflect actual work done

## Test Strategy

- [ ] Unit test: Template generation produces valid markdown
- [ ] Unit test: Divergence detector identifies new exports correctly
- [ ] Unit test: Divergence detector handles edge cases (renames, moves)
- [ ] Fixture: Sample spec + implementation pairs with known divergences
- [ ] Integration test: Full sync-spec cycle updates spec correctly

## Files to Create

| File | Purpose |
|------|---------|
| `plugins/soleur/skills/spec-templates/SKILL.md` | Spec and tasks templates |
| `plugins/soleur/commands/soleur/sync-spec.md` | Spec sync command |

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/commands/soleur/compound.md` | Add divergence check and sync |

## References

- Brainstorm: `docs/brainstorms/2026-02-05-unified-spec-workflow-brainstorm.md`
- Spec Artifact Format section
- Spec Evolution & Sync section
