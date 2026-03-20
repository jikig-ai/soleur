# Tier B: Subagent Fan-Out Protocol

Independent subagents that execute in parallel without peer-to-peer communication. (fire-and-gather, moderate cost)

## Step B1: Offer subagent fan-out

"I found N independent tasks that could run in parallel via subagents.
This uses more tokens but completes faster. Run in parallel?"

- If No: fall through to Tier C
- If Yes: continue to Step B2

## Step B2: Group and spawn subagents

Group independent tasks into clusters (max 5 groups). Each group gets one Task
general-purpose agent. Spawn all groups in parallel using a single message with
multiple Task tool calls:

```text
Task general-purpose: "You are executing part of a work plan.

BRANCH: [current branch name]
WORKING DIRECTORY: [current working directory path]

YOUR TASKS:
[Task descriptions and relevant plan sections for this group]

REFERENCED FILES:
[List files this group needs to read or modify]

INSTRUCTIONS:
- Read referenced files before modifying them
- Follow existing codebase patterns and conventions
- Write tests for new functionality
- Run tests relevant to your changes
- Do NOT commit -- the lead will commit after reviewing all work
- Do NOT modify files outside your assigned scope
- Report back: what you completed, files modified, any issues encountered"
```

## Step B3: Collect results and integrate

Wait for all subagents to complete. Then:

- Review each subagent's report for completeness and issues
- If any subagent failed or reported issues: complete those tasks
  sequentially using the task loop below
- Run the full test suite to verify integration across all parallel work
- If tests pass: create an incremental commit for the parallel batch
- If tests fail: fix integration issues, then commit
- Update TaskList to mark all completed tasks

Then proceed to the remaining dependent tasks (if any) using the sequential loop,
or skip directly to Phase 3 if all tasks are done.
