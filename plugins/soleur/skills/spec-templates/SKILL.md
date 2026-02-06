---
name: spec-templates
description: This skill provides standardized templates for feature specifications (spec.md) and task tracking (tasks.md). It should be used when creating new features in the knowledge-base/specs/ directory.
---

# Spec Templates

Provides templates for structured feature specifications.

## When to Use

- At the end of `soleur:brainstorm` to create spec.md
- At the end of `soleur:plan` to create tasks.md
- When starting any new feature in `knowledge-base/specs/`

## spec.md Template

Use this template for feature specifications:

```markdown
# Feature: [name]

## Problem Statement

[What problem are we solving?]

## Goals

- [What we want to achieve]

## Non-Goals

- [What is explicitly out of scope]

## Functional Requirements

### FR1: [name]

[User-facing behavior]

## Technical Requirements

### TR1: [name]

[Architecture, performance, security considerations]
```

## tasks.md Template

Use this template for task tracking:

```markdown
# Tasks: [name]

## Phase 1: Setup

- [ ] 1.1 Task description

## Phase 2: Core Implementation

- [ ] 2.1 Main task
  - [ ] 2.1.1 Subtask if needed

## Phase 3: Testing

- [ ] 3.1 Task description
```

## Directory Structure

Each feature gets its own directory:

```
knowledge-base/specs/feat-<name>/
  spec.md      # Requirements (FR/TR)
  tasks.md     # Phased task checklist
```

## Usage Examples

### Creating a spec for "user-auth" feature

1. Create directory: `knowledge-base/specs/feat-user-auth/`
2. Create `spec.md` using the template above
3. Fill in Problem Statement, Goals, Non-Goals
4. Add Functional Requirements (FR1, FR2, ...)
5. Add Technical Requirements (TR1, TR2, ...)

### Creating tasks from a spec

1. Read the spec.md to understand requirements
2. Create `tasks.md` using the template
3. Break down each FR/TR into concrete tasks
4. Organize into phases (Setup, Core, Testing)
5. Use hierarchical numbering (2.1, 2.1.1, etc.)
