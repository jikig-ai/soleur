# Feature: Agent Teams Integration

## Problem Statement

`/soleur:work` executes plan tasks sequentially, one at a time. For plans with multiple independent tasks, this wastes wall-clock time when tasks could run in parallel. Opus 4.6 Agent Teams enable true parallel execution with coordinated teammates, but they consume significantly more tokens -- requiring explicit user consent before activation.

## Goals

- Enable parallel task execution in `/soleur:work` using Opus 4.6 Agent Teams
- Provide a 3-tier execution model: Agent Teams > Subagent fan-out > Sequential
- Auto-detect parallelization opportunities from the plan's dependency graph
- Require user confirmation before engaging higher-cost execution modes
- Establish reusable consent and coordination patterns for other commands (v2)

## Non-Goals

- Integrating Agent Teams into other commands (v2 scope)
- Building a custom orchestration layer (use native Agent Teams API)
- Real-time progress dashboard UI
- Automatic cost estimation or token budgeting
- Nested teams (Agent Teams limitation: one team per session)

## Functional Requirements

### FR1: Plan Analysis

Analyze the plan's task list to build a dependency graph. Identify independent tasks (tasks with no blockers that can run in parallel). Determine the parallelization potential: count of independent task groups.

### FR2: Execution Mode Selection

When 3+ independent tasks are detected, present the user with the execution mode options:

1. **Agent Teams** -- spawn teammates for parallel execution (highest cost)
2. **Subagent fan-out** -- use Task tool for independent tasks (medium cost)
3. **Sequential** -- current behavior (lowest cost)

When fewer than 3 independent tasks exist, proceed with sequential execution without prompting.

### FR3: Agent Teams Execution

When Agent Teams mode is selected:
- Lead agent analyzes dependency graph, file overlap, and domain boundaries
- Lead determines optimal teammate count and task grouping
- Lead spawns teammates with task-specific context from the plan
- Teammates execute assigned tasks, committing incrementally
- Lead monitors progress and handles task dependencies (unblocking)
- Lead merges results and runs quality checks

### FR4: Subagent Fan-Out Execution

When subagent mode is selected:
- Spawn one Task tool subagent per independent task group
- Each subagent receives plan context and task assignment
- Results collected and integrated by the lead
- No inter-agent communication (fire-and-gather pattern)

### FR5: Hybrid Worktree Strategy

Default to shared worktree for all teammates. Before spawning, analyze file overlap between task groups. If file overlap is detected between groups:
- Create per-teammate worktrees for conflicting groups
- Lead merges worktree results after teammates complete
- Non-conflicting groups continue in shared worktree

### FR6: Graceful Fallback

If user declines Agent Teams, offer subagent mode. If user declines subagent mode, fall back to sequential. Each tier works independently without requiring the tier above.

## Technical Requirements

### TR1: Agent Teams Environment

Agent Teams require `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings or environment. The work command must verify this is set before offering Agent Teams mode. If not set, skip to subagent/sequential options.

### TR2: Dependency Graph Construction

Build a task dependency graph from the plan document. Tasks are independent when they have no shared blockers, no file overlap, and no data dependencies. The graph informs both the auto-detect threshold and the lead's grouping decisions.

### TR3: Worktree Management

Reuse the existing `worktree-manager.sh` infrastructure for per-teammate worktrees. Worktree naming: `.worktrees/feat-<name>-teammate-<N>`. Cleanup after merge.

### TR4: Error Recovery

If a teammate fails mid-task: the lead should reassign the failed task to another teammate or fall back to sequential execution for that specific task. Partial work from the failed teammate should be preserved if possible.

### TR5: Commit Coordination

In shared worktree mode, teammates should coordinate commits to avoid conflicts. In per-teammate worktree mode, each teammate commits independently and the lead merges. All commits follow existing incremental commit conventions.
