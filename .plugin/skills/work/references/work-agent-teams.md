# Tier A: Agent Teams Protocol

Persistent subagents with coordinated task assignments for plans where tasks share context or integration points. (~7x token cost)

## Step A1: Offer Agent Teams

Present the user with teammate count, task assignments, and cost context:

"I found N independent tasks that could run as an Agent Team.
This spawns persistent subagents that coordinate on shared work (~7x token cost).

Proposed assignments:

- Agent 1: [tasks]
- Agent 2: [tasks]
...

Run as Agent Team? (Or decline to try subagent fan-out instead)"

- If declined: fall through to Tier B
- If accepted: continue to Step A2

## Step A2: Spawn agents via delegate tool

Use the `delegate` tool to spawn and assign work to named subagents:

```
spawn: ["teammate-1", "teammate-2", ...]
delegate:
  teammate-1: "You are a teammate executing part of a work plan.

    BRANCH: [current branch name]
    WORKING DIRECTORY: [current working directory path]

    YOUR TASKS:
    [Task descriptions and relevant plan sections for this teammate]

    FILES YOU MAY MODIFY:
    [Explicit list of files this teammate is allowed to touch]

    INSTRUCTIONS:
    - Read AGENTS.md and referenced files before modifying them
    - Follow existing codebase patterns and conventions
    - Write tests for new functionality
    - Run tests relevant to your changes
    - Do NOT commit -- the lead will commit after reviewing all work
    - Do NOT modify files outside the list above"

  teammate-2: "..."
```

Assign overlapping tasks to the same agent to prevent file conflicts.

## Step A3: Monitor, test, and commit

If an agent fails: retry the task sequentially. Other agents continue unaffected.

When all agents complete:

- Run the full test suite to verify integration
- If tests pass: create incremental commits for the batch
- If tests fail: fix integration issues, then commit
- Update `task_tracker` to mark all completed tasks

Then proceed to the remaining dependent tasks (if any) using the sequential loop,
or skip directly to Phase 3 if all tasks are done.
