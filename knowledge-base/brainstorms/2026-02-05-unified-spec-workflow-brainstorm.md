# Unified Spec-Driven Workflow Enhancement

**Date:** 2026-02-05
**Status:** Brainstorm Complete - Ready for Planning

## What We're Building

Enhance Soleur to become a unified spec-driven development system combining the best of three approaches:

1. **From Spec-Kit:** Git worktree isolation per feature
2. **From OpenSpec:** Co-located specs that evolve alongside code
3. **From Soleur (current):** Agent swarms, parallel skills, compounding knowledge

Plus one additional capability:

- Constitutional principles (project-level rules guiding all work)

**Deferred for now (architect for later):**

- Multi-agent adapters (Claude Code only, but strategy pattern for extensibility)
- Shell completions (add when core workflow is stable)

## Why This Approach

**Layered Enhancement Architecture** - distinct composable layers that work together:

```text
+-------------------------------------------+
|  Commands Layer (soleur:*)                |
|  brainstorm -> spec -> plan -> work -> compound
+-------------------------------------------+
|  Worktree Layer (git isolation)           |
|  Each feature gets isolated worktree (feat-<name>)
+-------------------------------------------+
|  Spec Layer (knowledge-base/specs/)       |
|  Specs live in repo, evolve with code     |
+-------------------------------------------+
|  Constitution Layer                       |
|  Project principles that guide all work   |
+-------------------------------------------+
|  Compounding Layer (knowledge-base/learnings)      |
|  Time-decaying learnings, key principles  |
|  bubble up to constitution                |
+-------------------------------------------+
```

**Rationale:**

- Clean separation makes each layer testable and maintainable
- Can roll out incrementally (worktrees first, then spec evolution, etc.)
- Layers compose - a command can use any combination
- Easier to debug issues (isolate which layer is problematic)

## Key Decisions

### Workflow: Brainstorm -> Plan -> Work -> Compound

The full workflow for significant features:

1. **Brainstorm** (`soleur:brainstorm`) - Explore what to build, creates spec.md at end
2. **Plan** (`soleur:plan`) - Design implementation approach, creates tasks.md
3. **Work** (`soleur:work`) - Implement in isolated worktree
4. **Compound** (`soleur:compound`) - Capture learnings, sync spec, cleanup old learnings

### Command Flow & Entry Points

**Flexible Entry:** Users can enter the workflow at any point - not required to start from brainstorm.

**Entry Point Behaviors:**

| Enter At | Checks For | If Missing |
|----------|------------|------------|
| `brainstorm` | Nothing | Creates spec dir + worktree |
| `plan` | spec.md | Prompts: "Create spec first?" |
| `work` | spec.md, tasks.md | Prompts: "Create missing artifacts?" |
| `compound` | Any previous artifacts | Works with whatever exists |

**State Discovery:** Convention-based (no manifest file)

- Commands look for files in known locations
- Branch name `feat-<name>` maps to `knowledge-base/specs/feat-<name>/`
- Worktree location `.worktrees/feat-<name>/`

**Artifact Locations:**

```text
knowledge-base/specs/<feature-name>/
  spec.md          # Requirements (FR/TR)
  tasks.md         # Implementation tasks
  brainstorm.md    # Optional: captured from brainstorm session
```

**Command Chaining:**

Each command knows what comes next and suggests it:

```text
soleur:brainstorm -> creates spec.md -> "Ready to plan? Run soleur:plan"
soleur:plan       -> creates tasks.md -> "Ready to work? Run soleur:work"
soleur:work       -> implements -> "Done? Run soleur:compound"
soleur:compound   -> syncs & learns -> "Feature complete!"
```

**Note:** There is no separate `soleur:spec` command. Spec creation is the output of brainstorming.

### Directory Structure

```text
knowledge-base/
  specs/           # Feature specifications
  learnings/       # Session learnings (time-decaying)
  patterns/        # Extracted recurring patterns
  reviews/         # Review feedback memory
  constitution.md  # Project principles (top-level, always consulted)
```

**Rationale:** `knowledge-base/` is agent-agnostic and can be used by any AI coding assistant. `docs/` stays reserved for external-facing documentation.

### Git Worktree Workflow

**Naming:** `feat-<name>` (e.g., `feat-auth`, `feat-payment`)

**Use Cases:**

- Parallel features - work on multiple features simultaneously
- Agent isolation - each agent/task gets own worktree
- Review safety - keep main clean while experimenting

**Lifecycle:**

1. **Creation:** At brainstorm start (full isolation from the beginning)
2. **Location:** Default `.worktrees/feat-<name>`, user-configurable
3. **Navigation:** Interactive selector command to switch between worktrees
4. **Cleanup:** Automatic removal after PR merged to main

**Directory Structure:**

```text
my-project/
  .worktrees/
    feat-auth/       # Worktree for auth feature
    feat-payment/    # Worktree for payment feature
  knowledge-base/
    specs/
      feat-auth/
        spec.md
        tasks.md
      feat-payment/
        spec.md
        tasks.md
```

**Commands:**

- `soleur:brainstorm` - Creates worktree + spec files at start
- `soleur:switch` - Interactive picker to switch between worktrees
- Auto-cleanup on merge (detected via git hooks or PR status)

### Compounding & Knowledge Hierarchy

```text
Session learnings (detailed, time-decaying)
         |
         v  (agent suggests, user confirms)
    Constitution (concise, permanent)
```

- **Session learnings:** Captured in `knowledge-base/learnings/`, decay over ~6 months
- **Patterns:** Auto-extracted to `knowledge-base/patterns/`
- **Review memory:** Stored in `knowledge-base/reviews/`
- **Constitution:** Most important principles promoted to `constitution.md`
  - Kept concise to avoid context window bloat
  - Consulted by all commands/agents

### Learning Decay Mechanism

**Decay Period:** ~6 months from creation

**Tracking:** Filename-based dating

- Format: `YYYY-MM-DD-topic.md` (e.g., `2026-02-05-n1-query-fix.md`)
- Date extracted from filename prefix

**Cleanup Trigger:** During `soleur:compound`

- Check all files in `knowledge-base/learnings/`
- Compare filename date to current date
- Delete files older than 6 months

**What Gets Deleted:**

- Learnings older than 6 months that were NOT promoted to constitution
- Promoted learnings can also be deleted (the principle lives in constitution)

**Cleanup Flow:**

```text
soleur:compound:
1. Capture new learnings from session
2. Check for constitution promotion candidates
3. Delete learnings older than 6 months
4. Report: "Cleaned up 3 old learnings"
```

**Grace Period:** None - clean delete after 6 months. Important principles should have been promoted to constitution by then.

### Constitution Promotion Flow

**When:** During `soleur:compound` (at end of work session)

**Process:**

1. Agent reviews session learnings and existing learnings
2. Identifies candidates for constitution promotion based on:
   - Frequency (same insight appearing multiple times)
   - Impact (prevented significant issues or improved quality)
   - Generality (applies broadly, not just to one feature)
3. Suggests promotions to user with explanation
4. User approves/rejects each suggestion
5. Approved learnings distilled into single concise principle
6. Principle added to appropriate domain + Always/Never/Prefer category

**Distillation:**

- Extract key rule only (no context/rationale in constitution)
- Keep principles actionable and specific
- One principle per promotion (don't combine)

**Example Flow:**

```text
Agent: "I noticed we've had 3 sessions where we caught the same
       N+1 query issue. Suggest promoting to constitution?"

User: "Yes"

Agent: Adds to ## Architecture > ### Never:
       "- Lazy-load associations in serializers without includes"
```

### Pattern Extraction

**What:** Recurring approaches, code structures, or solutions that appear across multiple features.

**Detection:**

- **Agent-detected:** During compound, agent notices similar code/approaches across sessions
- **User-tagged:** User explicitly marks something as a pattern worth documenting

**Format:** `knowledge-base/patterns/YYYY-MM-DD-pattern-name.md`

```markdown
# Pattern: <name>

## Problem
[What problem does this pattern solve?]

## Solution
[Description of the approach]

## Example
[Code or usage example]

## When to Use
[Conditions when this pattern applies]
```

**Lifecycle:**

- Patterns don't decay (they're meant to be permanent reference)
- Can be deprecated/archived if no longer relevant
- Referenced in constitution if elevated to "Always use" status

### Review Memory

**What:** Feedback from code reviews (PR comments + soleur:review sessions) and how issues were resolved.

**Purpose:** Prevent repeating the same mistakes by surfacing relevant past feedback during similar work.

**Format:** `knowledge-base/reviews/YYYY-MM-DD-topic.md`

```markdown
# Review: <topic>

## Issue
[What was flagged in review]

## Context
[Where this occurred - file, feature, PR]

## Resolution
[How the issue was fixed]

## Prevention
[How to avoid this in the future]
```

**Usage:**

- During `soleur:plan` - surface relevant past reviews
- During `soleur:review` - check if current code repeats past issues
- Candidates for constitution promotion if same issue keeps appearing

**Lifecycle:**

- Reviews decay like learnings (~6 months)
- Important patterns get promoted to constitution

### Multi-Agent Strategy

- **Primary:** Claude Code (fully supported)
- **Architecture:** Strategy pattern for adapters
- **Deferred:** Cursor, Copilot, Gemini, Windsurf adapters (add when needed)

### Constitutional Principles

Project-level rules that:

- Establish core principles guiding all development
- Are consulted by all agents/commands
- Evolve as important learnings bubble up from sessions
- Stay concise (context window aware)

### Constitution Format

**`constitution.md`** - Categorized principles with Always/Never/Prefer within each domain:

```markdown
# Project Constitution

## Code Style

### Always
- [Principle that must be followed]

### Never
- [Anti-pattern to avoid]

### Prefer
- [Soft preference when applicable]

## Architecture

### Always
- [Architectural principle]

### Never
- [Anti-pattern]

### Prefer
- [Preferred approach]

## Testing

### Always
- [Testing practice]

### Never
- [What not to do]

### Prefer
- [Preferred approach]

## Documentation

### Always
- [Documentation requirement]

### Never
- [What to avoid]

### Prefer
- [Preferred style]

## Git & Workflow

### Always
- [Workflow rule]

### Never
- [Anti-pattern]

### Prefer
- [Preferred practice]

## Security

### Always
- [Security principle]

### Never
- [Security anti-pattern]

### Prefer
- [Security preference]

## CI/CD & DevSecOps

### Always
- [CI/CD principle]

### Never
- [Anti-pattern]

### Prefer
- [Preferred approach]

## Operations

### Always
- [Operational principle]

### Never
- [Anti-pattern]

### Prefer
- [Preferred practice]
```

**Domain Categories:**

1. Code Style
2. Architecture
3. Testing
4. Documentation
5. Git & Workflow
6. Security
7. CI/CD & DevSecOps
8. Operations

**Within Each Domain:**

- **Always** - Hard rules, must follow
- **Never** - Anti-patterns, avoid these
- **Prefer** - Soft preferences, use when applicable

### Spec Artifact Format (Two-File Approach)

**`spec.md`** - Pure markdown with headers:

```markdown
# Feature: <name>

## Context
[Optional background information]

## Problem Statement
[What problem are we solving?]

## Goals
- [What we want to achieve]

## Non-Goals
- [What is explicitly out of scope]

## Functional Requirements

### FR1: <requirement-name>
[What the system should do - user-facing behavior]

### FR2: <requirement-name>
...

## Technical Requirements

### TR1: <requirement-name>
[How it should be built - architecture, performance, security]

### TR2: <requirement-name>
...

## Constraints
[Optional: technical, time, resource constraints]
```

**`tasks.md`** - Grouped phases with hierarchical checkboxes:

```markdown
# Tasks: <feature-name>

## Phase 1: Setup
- [ ] 1.1 Task description
- [ ] 1.2 Task description

## Phase 2: Core Implementation
- [ ] 2.1 Main task
  - [ ] 2.1.1 Subtask
  - [ ] 2.1.2 Subtask
- [ ] 2.2 Another task

## Phase 3: Testing & Polish
- [ ] 3.1 Task description
```

**Rationale:**

- Two files only (vs OpenSpec's 4+) - simpler, less overhead
- Pure markdown - no YAML frontmatter, human-readable
- FR/TR split - separates "what" from "how"
- Checkboxes in tasks - trackable progress

### Spec Evolution & Sync

**Philosophy:** Specs should evolve with the code, not become stale documentation.

**Detection Triggers:**

- At compound time (`soleur:compound`) - automatic check
- Manual trigger (`soleur:sync-spec`) - on-demand

**Divergence Types Tracked:**

- New files/functions not in original spec
- Changed behavior vs specified behavior
- Scope changes (features added/removed)

**Auto-Update Behavior:**

When divergence detected, automatically update spec to match implementation:

1. Add new requirements for new functionality
2. Update existing requirements for changed behavior
3. Mark removed requirements as deprecated with reason
4. Regenerate tasks.md based on actual work done

**Spec History:**

Keep git history of spec changes - allows seeing how requirements evolved during implementation. Each spec update is a commit with message like "sync: spec updated to match implementation".

## Success Criteria

- [ ] Single `soleur:plan` or `soleur:brainstorm` command can scaffold spec + worktree
- [ ] Specs in `knowledge-base/specs/` update when implementation diverges
- [ ] Learnings from work sessions appear in `knowledge-base/learnings/`
- [ ] Important learnings promoted to `constitution.md` over time
- [ ] Constitutional principles influence plan and review agents
- [ ] Worktrees created with `feat-<name>` convention

## Open Questions (Resolved)

| Question | Decision |
|----------|----------|
| Spec storage location | `knowledge-base/specs/` |
| Worktree naming | `feat-<name>` |
| Agent adapter priority | Claude Code only, strategy pattern for later |
| Learning persistence | Time-decaying (~6mo), key principles to constitution |
| Shell completions | Skip for now |

## Next Steps

Run `/soleur:plan` to design the implementation approach for each layer.
