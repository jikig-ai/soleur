# Soleur Project Overview

Soleur is a Company-as-a-Service platform providing development tools that compound engineering knowledge over time. Every problem solved makes the next one easier.

## Purpose

Transform feature development from ad-hoc coding into a structured, repeatable workflow. The platform captures learnings, patterns, and solutions in a knowledge base that grows with the project.

## Architecture

```mermaid
graph TB
    subgraph "User Interface"
        CLI[Claude Code CLI]
    end

    subgraph "Entry Points"
        GO["/soleur:go"]
        SY["/soleur:sync"]
        HLP["/soleur:help"]
    end

    subgraph "Workflow Skills"
        BS["brainstorm"]
        PL["plan"]
        WK["work"]
        RV["review"]
        CP["compound"]
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

    CLI --> GO --> BS --> PL --> WK --> RV --> CP
    SY --> KB

    BS --> AG
    PL --> AG
    WK --> AG
    RV --> AG

    CM --> SK
    SK --> AG

    CP --> LN
    BS --> BR
    PL --> PLA
```

## The Workflow

```
brainstorm --> plan --> work --> review --> compound
```

Workflow stages are skills, invocable directly or via `/soleur:go`:

| Phase | Skill | Purpose |
|-------|-------|---------|
| 1. Explore | `soleur:brainstorm` | Clarify requirements, explore approaches, make design decisions |
| 2. Plan | `soleur:plan` | Create structured implementation plans with research |
| 3. Execute | `soleur:work` | Implement systematically with incremental commits |
| 4. Review | `soleur:review` | Multi-agent code review before PR |
| 5. Learn | `soleur:compound` | Capture learnings for future work |

**Additional skill:** `soleur:one-shot` -- Full autonomous engineering workflow from plan to PR.

**Commands** (entry points only):

| Command | Purpose |
|---------|---------|
| `/soleur:go` | Unified entry point that routes to workflow skills |
| `/soleur:sync` | Populate knowledge-base from existing codebase |
| `/soleur:help` | List all available Soleur commands, agents, and skills |

**For existing codebases:** Run `/soleur:sync` first to populate knowledge-base with conventions.

## Components

| Component | Count | Description |
|-----------|-------|-------------|
| [Agents](./components/agents.md) | 45 | AI agents for specialized tasks |
| [Commands](./components/commands.md) | 3 | Slash commands for entry points |
| [Skills](./components/skills.md) | 45 | Specialized capabilities |
| [Knowledge Base](./components/knowledge-base.md) | 1 | Documentation system |

Each component has detailed documentation in [components/](./components/) covering its purpose, available items, usage patterns, and conventions. See individual component docs for full reference.

## Constitution

The [constitution](./constitution.md) defines project principles organized by domain (Code Style, Architecture, Testing, Proposals, Specs, Tasks). Each domain uses **Always/Never/Prefer** categories to express rules at different levels of strictness.

Workflow skills like plan and work read the constitution automatically to guide decisions. `/soleur:sync` discovers new conventions from the codebase and writes them as constitution rules. The compound skill promotes learnings to constitution principles when appropriate.

## Directory Structure

```
soleur/
  plugins/soleur/           # The Claude Code plugin
    agents/                 # AI agents by category
      engineering/
        review/             # Code review agents
        design/             # Design agents
      research/             # Research and analysis
      workflow/             # Workflow automation
    commands/               # Slash commands
      soleur/               # Core workflow commands
    skills/                 # Specialized capabilities
    .claude-plugin/         # Plugin manifest
  knowledge-base/           # Project documentation
    learnings/              # Documented solutions
    specs/                  # Feature specifications
    brainstorms/            # Design explorations
    plans/                  # Implementation plans
    overview/               # This documentation
      constitution.md       # Coding conventions
```

## Key Concepts

### Compounding Engineering

Every solved problem contributes to the knowledge base. Future similar problems reference past solutions instead of being solved from scratch.

### Agent Hierarchy

Agents are organized by function:
- **Review agents** catch issues before PR
- **Research agents** gather context and best practices
- **Workflow agents** automate repetitive tasks

### Knowledge-Base Lifecycle

Knowledge artifacts follow a lifecycle: **create** during brainstorm/plan, **use** during work/review, **consolidate** into overview during compound, and **archive** to `*/archive/` directories after the feature ships. The overview (constitution.md, component docs, README.md) serves as the single source of truth -- individual brainstorms, plans, and specs are working documents that get archived once their insights are distilled.

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
/soleur:go <feature idea>
```

## See Also

- [Constitution](./constitution.md) - Project principles (Always/Never/Prefer rules by domain)
- [Agents](./components/agents.md) - AI agent categories and usage
- [Commands](./components/commands.md) - Slash command reference
- [Skills](./components/skills.md) - Specialized capabilities
- [Knowledge Base](./components/knowledge-base.md) - Documentation system structure
- [Plugin README](../../plugins/soleur/README.md) - Full component reference
- [Installation](../../README.md) - Setup instructions
