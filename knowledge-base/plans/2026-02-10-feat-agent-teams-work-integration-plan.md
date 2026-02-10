---
title: "feat: Agent Teams execution tier in /soleur:work"
type: feat
date: 2026-02-10
issue: "#26"
---

# Agent Teams Execution Tier in /soleur:work

## Overview

Add an Agent Teams execution block to Phase 2 of `work.md`, positioned before the existing subagent fan-out block. When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set and 3+ independent tasks exist, offer Agent Teams as the highest-capability parallel execution tier.

## Problem Statement

The subagent fan-out tier (#31) uses fire-and-gather Task tool spawns that cannot communicate. For plans with tasks that share context or integration points, persistent teammates with peer-to-peer messaging provide better coordination.

## Proposed Solution

Insert a new Agent Teams block into `plugins/soleur/commands/soleur/work.md` Phase 2, following the same detect/offer/execute pattern as the existing subagent block. The block uses the native TeammateTool API and team-aware Task tools.

### Phase 2 Flow After Change

```
Step 0: Agent Teams (NEW)
  -> Check env var
  -> If available + 3+ independent tasks -> offer with cost context
  -> If accepted -> ATDD: write tests first, then spawn team, execute, test, commit, cleanup
  -> If declined -> fall through

Step 1: Subagent fan-out (EXISTING, unchanged)
  -> If 3+ independent tasks -> offer
  -> If accepted -> spawn, collect, test, commit
  -> If declined -> fall through

Step 2-6: Sequential loop (EXISTING, unchanged)
```

### Agent Teams Block Structure

The new block has 5 steps:

**Step 0.1: Check environment and analyze independence**
- Verify `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- If not set, skip to Step 1 (existing subagent block)
- Reuse the same independence analysis as Step 1 (TaskList, `blockedBy`, file overlap)
- If fewer than 3 independent tasks, skip to Step 1

**Step 0.2: Offer Agent Teams**
- Use AskUserQuestion with teammate count, task assignments, and ~7x cost note
- If declined, fall through to Step 1 (subagent block)

**Step 0.3: Write acceptance tests (ATDD)**
- Before spawning teammates, the lead writes acceptance tests for the tasks that will be parallelized
- These tests define the expected behavior and serve as the integration verification gate
- Tests should be failing (red) at this point -- teammates will make them pass

**Step 0.4: Initialize team and spawn teammates**
- `spawnTeam` to initialize team directory
- Spawn teammates via Task tool with `team_name` parameter
- Each teammate receives: CLAUDE.md/constitution context, branch, working directory, assigned tasks, file list, instructions (no commits, mark tasks via TaskUpdate, do not modify unlisted files)

**Step 0.5: Monitor, test, and shutdown**
- Lead monitors progress via `TaskList`, coordinates via `write`/`broadcast`
- If a teammate fails: retry once, then lead completes that task sequentially
- When all tasks are marked complete: lead runs full test suite (while teammates are still alive)
- If tests fail: lead coordinates fixes with teammates via `write`
- If tests pass: lead creates incremental commits per logical unit
- Lead sends `requestShutdown`, then runs `cleanup`
- Proceed to remaining dependent tasks (sequential loop) or Phase 3

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
- Read referenced files before modifying them
- Follow existing codebase patterns and conventions
- Make the failing acceptance tests pass for your assigned tasks
- Run tests relevant to your changes
- Do NOT commit -- the lead will commit after reviewing all work
- Do NOT modify files outside the list above
- Mark each task as completed via TaskUpdate when done
- Message the lead via write if you need coordination or are blocked"
```

## Technical Considerations

- **Single file change:** Only `work.md` needs modification. The Agent Teams API is native to Claude Code -- no plugin infrastructure needed.
- **Pattern consistency:** Follows the same detect/offer/execute-or-fallthrough pattern as the subagent block.
- **ATDD flow:** Lead writes failing tests first, teammates implement to pass them. This provides an integration safety net before the lead commits.
- **File conflict risk:** Accepted for v1. Lead assigns explicit file lists to prevent overlap. Not enforced.
- **Team naming:** `soleur-{branch-name}` convention for uniqueness.

## Acceptance Criteria

- [ ] Agent Teams block added to work.md Phase 2, before existing subagent block
- [ ] Environment gate checks `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- [ ] Consent prompt shows teammate count, assignments, and ~7x cost note
- [ ] ATDD step: lead writes acceptance tests before spawning teammates
- [ ] Teammates spawned via Task tool with `team_name` parameter
- [ ] Teammate prompt includes explicit file list and no-commit instructions
- [ ] Lead monitors via TaskList, coordinates via write/broadcast
- [ ] Failed teammate gets one retry, then lead completes sequentially
- [ ] Tests run while teammates are alive (before shutdown)
- [ ] Lead creates incremental commits per logical unit
- [ ] Graceful shutdown: requestShutdown then cleanup
- [ ] Falls through to subagent block when declined or unavailable
- [ ] Plugin version bumped to 1.12.0
- [ ] CHANGELOG.md updated
- [ ] README.md counts verified

## Dependencies & Risks

- **Dependency:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be enabled by the user
- **Risk:** Experimental API may change. Mitigated by keeping the block thin and isolated.
- **Risk:** File conflicts in shared worktree. Mitigated by explicit file assignments (v1, best-effort).
- **Risk:** ~7x token cost. Mitigated by consent prompt with cost context.

## References

- Spec: `knowledge-base/specs/feat-agent-team/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-02-09-agent-team-brainstorm.md`
- Existing subagent block: `plugins/soleur/commands/soleur/work.md:138-200`
- Parallel execution learning: `knowledge-base/learnings/2026-02-09-parallel-subagent-fan-out-in-work-command.md`
- Plugin version: `plugins/soleur/.claude-plugin/plugin.json` (1.11.0 -> 1.12.0)
