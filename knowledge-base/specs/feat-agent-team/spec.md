# Feature: Agent Teams in /soleur:work

**Issue:** #26

## Problem Statement

`/soleur:work`'s subagent fan-out (#31) uses fire-and-gather spawns that cannot communicate with each other. For complex plans where tasks benefit from coordination, a higher-capability tier using Agent Teams is needed.

## Goals

- Add Agent Teams as the top execution tier in `/soleur:work`
- Peer-to-peer teammate coordination via shared task lists and messaging
- Auto-detect + confirm with clear cost context (~7x token cost)

## Non-Goals

- Agent Teams in other commands (future scope)
- Custom orchestration layer (use native Agent Teams API)
- Per-teammate worktrees
- Real-time progress dashboard UI
- Automatic cost estimation or token budgeting
- A2A protocol (v2 scope)

## Functional Requirements

### FR1: Auto-Managed Feature Flag

The `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` flag is activated automatically when the user accepts Agent Teams and deactivated after shutdown/cleanup or on spawnTeam failure. Users do not set it manually.

### FR2: Consent Flow

When 3+ independent tasks detected and Agent Teams available, offer it first (before subagent tier). The consent prompt must show:

- Proposed teammate count and task assignments
- Note about higher token cost (~7x)
- Option to decline (falls through to subagent block)

### FR3: Team Lifecycle

1. Lead initializes team via `spawnTeam`. If this fails (stale team), attempt `cleanup` and retry once, then fall through to subagent tier.
2. Lead spawns teammates via **Task tool with `team_name` parameter** -- the key API difference from regular subagents. Each teammate receives task-specific context + instructions (no commits, mark tasks via TaskUpdate).
3. Teammates self-claim and execute tasks from the shared task list.
4. Lead monitors progress via `TaskList` and coordinates via `write`/`broadcast`.
5. On completion: lead runs test suite, commits, sends `requestShutdown`, runs `cleanup`.

### FR4: Lead-Coordinated Commits

Teammates modify files but do NOT commit. Lead collects work, runs tests, commits atomically.

### FR5: Error Handling

Failed teammate gets one retry. If retry fails, lead completes that task sequentially. Other teammates continue unaffected.

### FR6: Graceful Shutdown

Lead sends `requestShutdown` to all teammates, waits for acknowledgment, then runs `cleanup` to remove team config and task files. Execution continues to Phase 3 (quality check).

## Technical Requirements

### TR1: work.md Changes

Restructure Phase 2 section 1 as a tiered execution mode selection (Tier A: Agent Teams, Tier B: Subagent Fan-Out, Tier C: Sequential). Agent Teams tier uses the same 4-step pattern as the subagent tier: check, ask, do, finish.

### TR2: TeammateTool Integration

Use native operations: `spawnTeam`, `write`, `broadcast`, `requestShutdown`, `cleanup`. Spawn teammates via Task tool with `team_name` parameter. Use team-aware Task tools (`TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`) for shared work items.

### TR3: Teammate Context

Each teammate receives:

- Teammates read CLAUDE.md / constitution.md from the working directory (not passed in prompt)
- Branch name and working directory
- Assigned task descriptions from the plan
- Instructions to NOT commit (lead-coordinated commits)
- Instructions to mark tasks as completed via TaskUpdate
- Teammates inherit the lead's permission mode (per-teammate permissions cannot be set at spawn)

### TR4: Shared Worktree

All teammates in same directory. Lead prevents file conflicts by assigning overlapping tasks to the same teammate.

## Risks

- **Token cost (~7x):** Mitigated by explicit consent with cost context in prompt.
- **Task status lag:** Teammates may forget to mark tasks complete. Mitigated by lead monitoring and `TaskCompleted` hook.
- **No session resumption:** Teammates lost on interrupt. Mitigated by lead-coordinated commits (files saved, not committed mid-work).
- **One team per session:** If user already has an active team, spawning fails. Mitigated by checking for existing teams before offering and running `cleanup` if stale.
- **Experimental API:** May change. Mitigated by keeping integration thin (one block in work.md).
