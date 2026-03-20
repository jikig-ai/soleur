---
module: Knowledge Base
date: 2026-02-06
problem_type: implementation_pattern
component: documentation
tags:
  - knowledge-base
  - documentation
  - project-overview
  - sync-command
  - onboarding
severity: info
---

# Project Overview Documentation System

## Context

The knowledge-base had conventions (constitution.md), feature specs, and learnings, but lacked high-level documentation describing the project's purpose and component architecture. This made onboarding harder for both developers and AI agents.

## Pattern

Create a dedicated `knowledge-base/overview/` directory with:

```text
overview/
  README.md              # Project purpose, architecture diagram, workflow
  components/
    agents.md            # One file per logical domain
    commands.md
    skills.md
    knowledge-base.md
```

Each component file uses consistent structure:

- YAML frontmatter (component, updated, primary_location)
- Purpose section (what it does)
- Responsibilities section (bullet points)
- Key Interfaces section (code examples)
- Data Flow section (mermaid diagram)
- Dependencies, Examples, Related Files sections

## Key Insights

### Separation of concerns for documentation

Keep "what" (overview) separate from "how" (constitution). They serve different purposes:

- `overview/` documents what the project does
- `constitution.md` documents how to work on it

### Logical organization beats source tree mirroring

Component boundaries should reflect architectural concepts, not file paths. "Agents" as a concept is more useful than mirroring the `agents/review/`, `agents/research/` directory structure.

### AI agents benefit from structured component docs

Mermaid diagrams, responsibility lists, and interface examples provide the context AI needs to make informed changes. Dual audience (human + AI) considerations matter.

### DoD should match tasks, not be predetermined

The spec listed specific file names (cli.md, plugins.md) before tasks were defined. The actual tasks created different logical groupings (agents.md, commands.md) that better matched codebase reality. Update DoD when tasks evolve.

### Verify docs against reality before trusting them

AGENTS.md described a "Bun/TypeScript CLI that converts plugins" but `src/` was empty. Treat documentation about "what exists" as a hypothesis to verify, not a fact to assume. The implementation is the source of truth.

### Convention enforcement needs tooling

Constitution.md stated "All markdown files must pass markdownlint" but without a config file, pre-commit hook, or CI check. Stated but unenforced conventions create false expectations. Either add tooling or remove the rule.

## Examples

Component file structure:

```markdown
---
component: agents
updated: 2026-02-06
primary_location: plugins/soleur/agents/
---

# Agents

[Purpose paragraph]

## Responsibilities

- Bullet list

## Key Interfaces

[Code examples]

## Data Flow

[Mermaid diagram]
```

## Related Files

- `knowledge-base/overview/README.md` - Main overview
- `knowledge-base/overview/components/` - Component documentation
- `plugins/soleur/commands/soleur/sync.md` - /sync command with overview area
- `plugins/soleur/skills/spec-templates/SKILL.md` - Component template
