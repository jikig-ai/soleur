---
component: knowledge-base
updated: 2026-02-06
primary_location: knowledge-base/
---

# Knowledge Base

A structured documentation system that captures conventions, learnings, specifications, and plans. The knowledge base grows with the project, making each problem easier to solve than the last.

## Purpose

Compound engineering knowledge over time. Every solved problem, design decision, and lesson learned is captured in a searchable, referenceable format that future work can build upon.

## Responsibilities

- Store project conventions and coding standards
- Capture learnings from debugging and implementation
- Track feature specifications through their lifecycle
- Document brainstorms and design decisions
- Maintain implementation plans

## Key Interfaces

**Directory structure:**

```
knowledge-base/
  project/                # Project meta + feature lifecycle
    constitution.md       # Project conventions (Always/Never/Prefer)
    brainstorms/          # Design explorations
    learnings/            # Documented solutions and patterns
      implementation-patterns/
      architecture/
      technical-debt/
    plans/                # Implementation plans
    specs/
      feat-<name>/        # Feature specifications
        spec.md
        tasks.md
      archive/            # Completed specs
      external/           # External platform specs
```

**File naming conventions:**

| Type | Pattern |
|------|---------|
| Brainstorms | `YYYY-MM-DD-<topic>-brainstorm.md` |
| Plans | `YYYY-MM-DD-<type>-<name>-plan.md` |
| Learnings | `<descriptive-name>.md` |
| Specs | `feat-<name>/spec.md` |

## Data Flow

```mermaid
graph TB
    subgraph "Input"
        BS[/brainstorm] --> BR[brainstorms/]
        PL[/plan] --> PLA[plans/]
        CP[/compound] --> LN[learnings/]
        SY[/sync] --> CON[constitution.md]
    end

    subgraph "Knowledge Base"
        BR
        PLA
        LN
        CON
        SP[specs/]
        OV[project/]
    end

    subgraph "Output"
        BR -->|informs| PL2[/plan]
        LN -->|informs| WK[/work]
        CON -->|guides| ALL[All commands]
        SP -->|tracks| WK
    end
```

1. `/brainstorm` creates documents in `brainstorms/`
2. `/plan` creates documents in `plans/`
3. `/compound` creates documents in `learnings/`
4. `/sync` updates `constitution.md` with conventions
5. All commands read from knowledge base to inform their work

## Subdirectories

### constitution.md

Project principles organized by domain (Code Style, Architecture, Testing, etc.). Each domain has:
- **Always**: Rules that must be followed
- **Never**: Anti-patterns to avoid
- **Prefer**: Guidelines when multiple options exist

### learnings/

Documented solutions categorized by type:
- `implementation-patterns/` - How to implement specific features
- `architecture/` - Architectural decisions and patterns
- `technical-debt/` - Known issues and planned improvements

**Learnings format:**

```yaml
---
module: Authentication
date: 2026-02-06
problem_type: best_practice
tags: [auth, security]
severity: info
---

# Title

## Context
## Pattern
## Examples
## Key Insight
```

### specs/

Feature specifications with lifecycle management:
- `feat-<name>/spec.md` - Active feature specs
- `feat-<name>/tasks.md` - Implementation tasks
- `archive/` - Completed feature specs
- `external/` - Third-party platform specifications

### brainstorms/

Design explorations before implementation. Captures:
- What we're building and why
- Key decisions and rationale
- Open questions
- Chosen approach

### plans/

Implementation plans with detailed tasks. Created by `/plan`, executed by `/work`.

### project/

This documentation. Describes what the project does and its component architecture.

## Dependencies

- **Internal**: All workflow commands read/write here
- **External**: None (pure markdown)

## Examples

**Find relevant learnings:**

```bash
# Search for authentication patterns
grep -r "auth" knowledge-base/project/learnings/
```

**Check active specs:**

```bash
ls knowledge-base/project/specs/feat-*/
```

**Read conventions:**

```bash
cat knowledge-base/project/constitution.md
```

## Conventions

From `constitution.md`:

- Use convention over configuration for paths: `feat-<name>` maps to `knowledge-base/project/specs/feat-<name>/`
- Use Given/When/Then format for scenarios in specs
- Break tasks into chunks of max 2 hours
- Commands should check for `knowledge-base/` existence and fall back gracefully

## Related Files

- `knowledge-base/project/constitution.md` - Project conventions
- `knowledge-base/project/learnings/` - Documented solutions
- `knowledge-base/project/specs/` - Feature specifications
- `knowledge-base/project/brainstorms/` - Design explorations
- `knowledge-base/project/plans/` - Implementation plans

## See Also

- [Commands](./commands.md) - Commands that populate knowledge base
- [README](../README.md) - Project overview
