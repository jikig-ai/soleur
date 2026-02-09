---
name: spec-templates
description: This skill should be used when creating structured feature specifications and task tracking documents. It provides standardized templates for spec.md, tasks.md, and component.md in the knowledge-base/ directory. Triggers on "create a spec", "write a feature spec", "create tasks for feature", "new feature template", "spec template", "component documentation".
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

## component.md Template

Use this template for project overview component documentation in `knowledge-base/overview/components/`:

```markdown
---
component: <component-name>
updated: YYYY-MM-DD
primary_location: <path/to/component/>
related_locations:
  - <other/path>
---

# <Component Name>

[One paragraph - what this component does]

## Purpose

[Why this component exists and its role in the system]

## Responsibilities

- [Key responsibility 1]
- [Key responsibility 2]

## Key Interfaces

[Public APIs, entry points, exported types]

## Data Flow

[How data enters and exits this component - include mermaid diagram if helpful]

## Dependencies

- **Internal**: [other components it uses]
- **External**: [third-party packages]

## Examples

[Usage examples with code]

## Related Files

- `path/to/file` - [description]

## See Also

- [constitution.md](../constitution.md) for coding conventions
- [Related component](./related.md)
```

### YAML Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `component` | Yes | Kebab-case component name |
| `updated` | Yes | Date last updated (YYYY-MM-DD) |
| `primary_location` | Yes | Main directory/file path |
| `related_locations` | No | Additional paths if component spans directories |
| `status` | No | `active`, `deprecated` (default: active) |

### Creating a component doc

1. Identify the logical component (not just directory structure)
2. Create `knowledge-base/overview/components/<name>.md`
3. Fill in frontmatter with accurate paths
4. Document purpose, responsibilities, and interfaces
5. Add data flow diagram if the component has complex interactions
6. Link to related files and other components
