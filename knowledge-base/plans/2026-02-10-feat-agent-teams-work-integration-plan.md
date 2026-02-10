---
title: "feat: Agent Teams execution tier in /soleur:work"
type: feat
date: 2026-02-10
issue: "#26"
---

# Agent Teams Execution Tier in /soleur:work

## Overview

Add an Agent Teams execution tier to Phase 2 of `work.md`, positioned before the existing subagent fan-out tier. When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set and 3+ independent tasks exist, offer Agent Teams as the highest-capability parallel execution option.

## Problem Statement

The subagent fan-out tier (#31) uses fire-and-gather spawns that cannot communicate. For plans with tasks that share context or integration points, persistent teammates with peer-to-peer messaging provide better coordination.

## Proposed Solution

Restructure Phase 2 section 1 from "Parallel Execution (optional)" into an "Execution Mode Selection" section with three tiers:

```
1. **Execution Mode Selection**

   **Tier A: Agent Teams** (NEW -- highest capability, ~7x cost)
     -> Check env var + 3+ independent tasks -> offer -> execute or fall through

   **Tier B: Subagent Fan-Out** (EXISTING, unchanged)
     -> 3+ independent tasks -> offer -> execute or fall through

   **Tier C: Sequential** (EXISTING default)
     -> Proceed to task loop
```

### Agent Teams Tier (4 steps)

Mirrors the existing subagent pattern: check, ask, do, finish.

**Step 1: Check environment and analyze independence**
- Verify `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- If not set, skip to Tier B
- Reuse the same independence analysis (TaskList, `blockedBy`, file overlap)
- If fewer than 3 independent tasks, skip to Tier B

**Step 2: Offer Agent Teams**
- Use AskUserQuestion with teammate count, task assignments, and ~7x cost note
- If declined, fall through to Tier B

**Step 3: Initialize team and spawn teammates**
- `spawnTeam` to initialize team directory
- If `spawnTeam` fails (stale team exists): attempt `cleanup`, retry once, then fall through to Tier B
- Spawn teammates via Task tool with `team_name` parameter
- Teammates read CLAUDE.md/constitution from the working directory (not passed in prompt)

**Step 4: Monitor, test, commit, and shutdown**
- Lead monitors progress via `TaskList`, coordinates via `write`/`broadcast`
- If a teammate fails, lead completes that task sequentially
- When all tasks complete: run full test suite, create incremental commits, `requestShutdown`, `cleanup`

### Teammate Spawn Prompt Template

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

## Technical Considerations

- **Single file change:** Only `work.md` needs modification.
- **Pattern consistency:** 4-step structure mirrors the existing subagent tier.
- **Peer-to-peer messaging:** `write`/`broadcast` differentiate Agent Teams from subagents -- teammates can coordinate on shared context and integration points.
- **File conflict risk:** Accepted for v1. Lead assigns explicit file lists. Not enforced.
- **Team naming:** `soleur-{branch-name}` convention.
- **spawnTeam failure:** Cleanup stale team, retry once, then fall through to Tier B.

## Acceptance Criteria

- [x] Agent Teams tier added to work.md Phase 2, before existing subagent tier
- [x] Gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- [x] Consent prompt shows teammate count, assignments, and ~7x cost note
- [x] `spawnTeam` failure handled: cleanup stale team, retry, fall through
- [x] Falls through cleanly to subagent tier when unavailable or declined
- [x] Tests run after teammate completion, before commit
- [x] Plugin version bumped to 1.13.0, CHANGELOG and README updated

## References

- Spec: `knowledge-base/specs/feat-agent-team/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-02-09-agent-team-brainstorm.md`
- Existing subagent block: `plugins/soleur/commands/soleur/work.md:138-200`
- Plugin version: `plugins/soleur/.claude-plugin/plugin.json` (1.12.0 -> 1.13.0)
