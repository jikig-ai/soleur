---
title: Knowledge Base Project Overview System
status: draft
issue: 16
branch: feat-project-overview
created: 2026-02-06
---

# Knowledge Base Project Overview System

## Problem Statement

The knowledge-base has conventions (constitution.md), feature specs, and learnings, but lacks a high-level document describing what the project does and its component architecture. This makes it harder for both new developers and AI agents to understand the project's purpose and structure.

## Goals

1. **G1:** Provide a clear project overview accessible to both humans and AI agents
2. **G2:** Document each logical component with comprehensive detail (diagrams, examples, data flows)
3. **G3:** Integrate with `/sync` command for automatic updates as codebase evolves
4. **G4:** Maintain clear separation from constitution.md (what vs how)

## Non-Goals

- Replacing or merging with constitution.md
- Auto-generating API documentation (separate concern)
- Mirroring source code directory structure exactly
- Supporting multiple output formats (markdown only)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Create `knowledge-base/overview/README.md` with project purpose, high-level architecture, and quick links |
| FR2 | Create `knowledge-base/overview/components/` directory with one file per logical domain |
| FR3 | Component files must include: purpose, responsibilities, key interfaces, data flows, diagrams, and examples |
| FR4 | Overview links to constitution.md for conventions but does not duplicate content |
| FR5 | Add `overview` as a new area to `/sync` command |
| FR6 | `/sync all` must include overview area automatically |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Component files follow a standard template for consistency |
| TR2 | Diagrams use mermaid syntax for portability |
| TR3 | `/sync overview` analyzes code structure to detect components |
| TR4 | New component detection based on directory structure and module boundaries |

## Proposed Structure

```
knowledge-base/overview/
  README.md              # Project purpose, architecture overview, quick links
  components/
    cli.md               # CLI interface, commands, arguments
    plugins.md           # Plugin system, loading, configuration
    converters.md        # Conversion logic between formats
    targets.md           # Target providers (OpenCode, etc.)
  diagrams/
    architecture.md      # High-level architecture diagram
    data-flow.md         # How data flows through the system
```

## Scenarios

### Scenario: New developer onboarding

**Given** a developer new to the project
**When** they read `knowledge-base/overview/README.md`
**Then** they understand the project's purpose and can navigate to component details

### Scenario: AI agent understanding codebase

**Given** an AI agent asked to modify the plugin system
**When** it reads `knowledge-base/overview/components/plugins.md`
**Then** it understands plugin architecture, interfaces, and constraints before making changes

### Scenario: Syncing overview after adding new component

**Given** a developer adds a new logical component to the codebase
**When** they run `/sync overview`
**Then** the command detects the new component and prompts to create its documentation

## Open Questions

1. What heuristics should `/sync overview` use to detect "components"? (directory with >N files? explicit markers?)
2. Should the component template be a skill or hardcoded in sync?
3. How to handle components that span multiple directories?

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-06-project-overview-brainstorm.md`
- Related issue: #14
