# Soleur Project Overview

Soleur is a Claude Code plugin providing AI-powered development tools that compound engineering knowledge over time. Every problem solved makes the next one easier.

## Purpose

Transform feature development from ad-hoc coding into a structured, repeatable workflow. The plugin captures learnings, patterns, and solutions in a knowledge base that grows with the project.

## Architecture

```mermaid
graph TB
    subgraph "User Interface"
        CLI[Claude Code CLI]
    end

    subgraph "Core Workflow"
        BS[/soleur:brainstorm]
        PL[/soleur:plan]
        WK[/soleur:work]
        RV[/soleur:review]
        CP[/soleur:compound]
        SY[/soleur:sync]
    end

    subgraph "Components"
        AG[Agents]
        CM[Commands]
        SK[Skills]
    end

    subgraph "Knowledge Base"
        KB[knowledge-base/]
        CON[constitution.md]
        LN[learnings/]
        SP[specs/]
        BR[brainstorms/]
        PLA[plans/]
    end

    CLI --> BS --> PL --> WK --> RV --> CP
    SY --> KB

    BS --> AG
    PL --> AG
    WK --> AG
    RV --> AG

    CM --> AG
    CM --> SK

    CP --> LN
    BS --> BR
    PL --> PLA
```

## The Workflow

```
/soleur:brainstorm --> /soleur:plan --> /soleur:work --> /soleur:review --> /soleur:compound
```

| Phase | Command | Purpose |
|-------|---------|---------|
| 1. Explore | `/soleur:brainstorm` | Clarify requirements, explore approaches, make design decisions |
| 2. Plan | `/soleur:plan` | Create structured implementation plans with research |
| 3. Execute | `/soleur:work` | Implement systematically with incremental commits |
| 4. Review | `/soleur:review` | Multi-agent code review before PR |
| 5. Learn | `/soleur:compound` | Capture learnings for future work |

**For existing codebases:** Run `/soleur:sync` first to populate knowledge-base with conventions.

## Components

| Component | Count | Description |
|-----------|-------|-------------|
| [Agents](./components/agents.md) | 28 | AI agents for specialized tasks |
| [Commands](./components/commands.md) | 25 | Slash commands for workflow |
| [Skills](./components/skills.md) | 16 | Specialized capabilities |
| [Knowledge Base](./components/knowledge-base.md) | 1 | Documentation system |

## Directory Structure

```
soleur/
  plugins/soleur/           # The Claude Code plugin
    agents/                 # AI agents by category
      review/               # Code review agents
      research/             # Research and analysis
      design/               # Design and UI agents
      workflow/             # Workflow automation
      docs/                 # Documentation agents
    commands/               # Slash commands
      soleur/               # Core workflow commands
    skills/                 # Specialized capabilities
    .claude-plugin/         # Plugin manifest
  knowledge-base/           # Project documentation
    constitution.md         # Coding conventions
    learnings/              # Documented solutions
    specs/                  # Feature specifications
    brainstorms/            # Design explorations
    plans/                  # Implementation plans
    overview/               # This documentation
```

## Key Concepts

### Compounding Engineering

Every solved problem contributes to the knowledge base. Future similar problems reference past solutions instead of being solved from scratch.

### Agent Hierarchy

Agents are organized by function:
- **Review agents** catch issues before PR
- **Research agents** gather context and best practices
- **Design agents** verify UI implementations
- **Workflow agents** automate repetitive tasks
- **Doc agents** generate documentation

### Convention Over Configuration

Paths follow predictable patterns:
- Feature branches: `feat-<name>`
- Specs: `knowledge-base/specs/feat-<name>/`
- Worktrees: `.worktrees/feat-<name>/`

## Quick Start

```bash
# Install the plugin
claude plugin install soleur

# For existing projects, sync first
/soleur:sync

# Start the workflow
/soleur:brainstorm <feature idea>
```

## See Also

- [constitution.md](../constitution.md) - Coding conventions
- [Plugin README](../../plugins/soleur/README.md) - Full component reference
- [Installation](../../README.md) - Setup instructions
