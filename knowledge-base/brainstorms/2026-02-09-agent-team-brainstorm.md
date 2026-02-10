# Brainstorm: Agent Teams in /soleur:work

**Date:** 2026-02-10
**Issue:** #26
**Branch:** `feat-agent-team`

## What We're Building

Add an Agent Teams execution mode to `/soleur:work`. When a plan has 3+ independent tasks and the user has Agent Teams enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), offer to spawn persistent teammates that coordinate via shared task lists and peer-to-peer messaging.

This sits above the existing subagent fan-out (#31) as a higher-capability, higher-cost option. Falls back to subagents if declined or unavailable.

## Why Agent Teams Over Subagents

Subagents are fire-and-gather: they execute a task and report back. Agent Teams teammates are persistent sessions that can message each other, self-coordinate via shared task lists, and be directly messaged by the user. This matters for plans where tasks have soft dependencies -- shared context, design decisions, or integration points that benefit from discussion.

## Key Decisions

1. **Auto-detect + confirm** -- same UX as subagent tier. Show proposed teammate count and ~7x cost context, require confirmation.
2. **Shared worktree** -- all teammates work in the same directory. Lead prevents file conflicts through smart task assignment.
3. **Lead-coordinated commits** -- teammates do NOT commit. Lead collects work, runs tests, commits.
4. **Dynamic teammate count** -- lead proposes based on plan analysis, user confirms.
5. **Retry once then fallback** -- failed teammate gets one retry, then lead completes the task sequentially.
6. **Same model for teammates** -- Opus (same as lead).

## API Surface

**TeammateTool operations:**

- `spawnTeam` / `cleanup` -- initialize and tear down team directory + config
- `write` (direct message) / `broadcast` (all teammates) -- peer-to-peer messaging
- `requestShutdown` / `approveShutdown` -- graceful termination

**Teammate spawning:** Teammates are spawned via the **Task tool with a `team_name` parameter** (not via TeammateTool). This is the key API difference from regular subagents -- adding `team_name` makes the spawned agent a team-aware teammate with access to the shared task list and messaging.

**Team-aware Task tools:** `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet` -- when a team is active, these operate on shared state visible to all teammates. Includes owner assignment, dependency tracking, and file-based locking.

**Hooks:**

- `TeammateIdle` -- runs when a teammate is about to go idle. Exit code 2 sends feedback and keeps the teammate working.
- `TaskCompleted` -- runs when a task is marked complete. Exit code 2 prevents completion and sends feedback (quality gate).

**File-based state:**

- Team config: `~/.claude/teams/{team-name}/config.json`
- Shared tasks: `~/.claude/tasks/{team-name}/`

## Execution Flow

1. Check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set
2. Analyze task list for 3+ independent tasks (reuses #31 logic)
3. Offer Agent Teams with proposed teammate count, assignments, and ~7x cost note
4. If accepted: `spawnTeam` to initialize, then spawn teammates via Task tool with `team_name`
5. Teammates self-claim tasks from shared list, execute work, message each other as needed
6. Lead monitors progress via `TaskList`, sends coordination messages via `write`/`broadcast`
7. All tasks complete -> lead runs test suite -> lead commits -> `requestShutdown` + `cleanup`
8. If declined: fall through to existing subagent block

## Open Questions

- **Progress reporting** -- rely on built-in `Ctrl+T` shared task list, or add lead-logged summaries? Defer to implementation.
- **A2A protocol** -- v2 target per issue comment. Out of scope.
