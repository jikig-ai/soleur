---
component: commands
updated: 2026-02-12
primary_location: plugins/soleur/commands/soleur/
---

# Commands

Slash commands that users invoke to perform development tasks. Commands are markdown files containing instructions that Claude executes when the user types the command.

## Purpose

Provide user-facing entry points for the development workflow. Commands orchestrate agents, manage the knowledge base, and guide users through structured processes.

## Responsibilities

- Accept user input and parse arguments
- Coordinate multiple agents when needed
- Read and write to the knowledge base
- Guide users through multi-step workflows
- Provide consistent, repeatable processes

## Key Interfaces

**Invocation:** Users type the command name prefixed with `/`:

```
/soleur:plan feat-authentication
```

**Definition:** Commands are markdown files with YAML frontmatter:

```yaml
---
name: soleur:plan
description: Create implementation plans
argument-hint: "[path-to-spec]"
---

# Command Title

Instructions for Claude to follow...
```

## Data Flow

```mermaid
graph LR
    U[User] -->|"/command"| CC[Claude Code]
    CC -->|Loads| CMD[Command.md]
    CMD -->|Spawns| AG[Agents]
    CMD -->|Reads/Writes| KB[Knowledge Base]
    CMD -->|Returns| U
```

1. User types `/soleur:command` in Claude Code
2. Claude Code loads the command markdown file
3. Claude follows instructions, invoking agents as needed
4. Command reads/writes knowledge base files
5. Results returned to user

## Commands (8)

All commands use the `soleur:` prefix to avoid collisions with built-in commands. There are no top-level utility commands -- former utility commands were converted to skills in v1.17.0-v1.18.0.

| Command | Purpose |
|---------|---------|
| `/soleur:brainstorm` | Explore requirements, make design decisions |
| `/soleur:plan` | Create implementation plans with research |
| `/soleur:work` | Execute plans with incremental commits |
| `/soleur:review` | Multi-agent code review before PR |
| `/soleur:compound` | Capture learnings for future work |
| `/soleur:sync` | Populate knowledge base from existing codebase |
| `/soleur:help` | List all available Soleur commands, agents, and skills |
| `/soleur:one-shot` | Full autonomous engineering workflow from plan to PR |

## Workflow Sequence

```mermaid
sequenceDiagram
    participant U as User
    participant B as /brainstorm
    participant P as /plan
    participant W as /work
    participant R as /review
    participant C as /compound

    U->>B: Start with idea
    B->>U: Design decisions documented
    U->>P: Create plan
    P->>U: Implementation plan ready
    U->>W: Execute plan
    W->>U: Code implemented
    U->>R: Review before PR
    R->>U: Issues identified
    U->>C: Capture learnings
    C->>U: Knowledge compounded
```

## Dependencies

- **Internal**: Agents (invoked via Task tool), Skills (for specialized capabilities)
- **External**: Claude Code CLI, GitHub CLI (for PR operations)

## Examples

**Start a new feature:**

```
/soleur:brainstorm Add user authentication with OAuth
```

**Execute an existing plan:**

```
/soleur:work knowledge-base/plans/2026-02-06-feat-auth-plan.md
```

**Review before PR:**

```
/soleur:review
```

## Related Files

- `plugins/soleur/commands/soleur/` - All command definitions

## See Also

- [Agents](./agents.md) - Agents invoked by commands
- [Skills](./skills.md) - Skills used by commands
- [constitution.md](../constitution.md) - Command conventions
