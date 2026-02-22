# Tier A: Agent Teams Protocol

Persistent teammates with peer-to-peer messaging for plans where tasks share context or integration points. (~7x token cost)

## Step A1: Offer Agent Teams

Present the user with teammate count, task assignments, and cost context:

"I found N independent tasks that could run as an Agent Team.
This spawns persistent teammates that can coordinate via messaging (~7x token cost).

Proposed assignments:
- Teammate 1: [tasks]
- Teammate 2: [tasks]
...

Run as Agent Team? (Or decline to try subagent fan-out instead)"

- If declined: fall through to Tier B
- If accepted: continue to Step A2

## Step A2: Activate Agent Teams and initialize

Enable the experimental Agent Teams feature and initialize the team:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

Then initialize the team directory with `spawnTeam`:

```text
spawnTeam("soleur-{branch}")
```

If `spawnTeam` fails (stale team exists): attempt `cleanup`, retry once.
If retry still fails, deactivate the flag and fall through to Tier B:

```bash
unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
```

## Step A3: Spawn teammates

Spawn teammates via Task tool with `team_name` parameter. Each teammate receives
task-specific context and instructions:

```text
Task general-purpose (team_name="soleur-{branch}"): "You are a teammate
executing part of a work plan.

BRANCH: [current branch name]
WORKING DIRECTORY: [current working directory path]

YOUR TASKS:
[Task descriptions and relevant plan sections for this teammate]

FILES YOU MAY MODIFY:
[Explicit list of files this teammate is allowed to touch]

INSTRUCTIONS:
- Read CLAUDE.md and referenced files before modifying them
- Follow existing codebase patterns and conventions
- Write tests for new functionality
- Run tests relevant to your changes
- Do NOT commit -- the lead will commit after reviewing all work
- Do NOT modify files outside the list above
- Mark each task as completed via TaskUpdate when done"
```

Assign overlapping tasks to the same teammate to prevent file conflicts.

## Step A4: Monitor, test, commit, and shutdown

Lead monitors progress via `TaskList` and coordinates via `write`/`broadcast`.

If a teammate fails: retry once via the team. If retry fails, lead completes
that task sequentially. Other teammates continue unaffected.

When all tasks complete:

- Run the full test suite to verify integration
- If tests pass: create incremental commits for the batch
- If tests fail: fix integration issues, then commit
- Send `requestShutdown` to all teammates
- Run `cleanup` to remove team config and task files
- Deactivate the experimental flag:

  ```bash
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
  ```

- Update TaskList to mark all completed tasks

Then proceed to the remaining dependent tasks (if any) using the sequential loop,
or skip directly to Phase 3 if all tasks are done.
