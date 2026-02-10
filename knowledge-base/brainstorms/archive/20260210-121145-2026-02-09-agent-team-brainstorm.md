# Brainstorm: Agent Teams Integration

**Date:** 2026-02-09
**Issue:** #26
**Branch:** `feat-agent-team`
**Status:** Complete

## What We're Building

Integrate Opus 4.6 Agent Teams into `/soleur:work` to enable parallel task execution. When a plan has multiple independent tasks, the lead agent can spawn teammates to work on them simultaneously, dramatically reducing wall-clock time for multi-task plans.

The feature introduces a **3-tier execution model**:

1. **Agent Teams** -- full parallel teammates with shared task list, inter-agent messaging, and coordinated commits. Highest capability, highest token cost.
2. **Subagent fan-out** -- Task tool spawns for independent tasks. Cheaper, no inter-agent communication, suitable for truly independent work.
3. **Sequential** (current default) -- one task at a time. Lowest cost, always available as fallback.

## Why This Approach

### Auto-detect + confirm consent flow

Rather than forcing users to remember flags or configure settings, the system analyzes the plan's dependency graph automatically. If 3+ independent tasks are detected, it suggests Agent Teams and asks for confirmation. This gives power users parallelization without friction while protecting against surprise token costs.

The consent prompt surfaces:
- Number of independent tasks detected
- Estimated teammate count
- Clear option to decline (with subagent or sequential fallback)

### 3-tier fallback

When Agent Teams are declined, offering subagent mode (Task tool fan-out) provides a middle ground. This reuses the existing infrastructure -- `/soleur:review` and `/deepen-plan` already spawn multiple subagents successfully. Sequential mode remains for simple plans or cost-conscious users.

### Lead-decides task grouping

The lead agent analyzes the plan's dependency graph, file overlap, and domain boundaries to determine optimal teammate count and task assignment. This is better than rigid 1:1 or domain-based grouping because:
- Small plans (3-4 tasks) might get 2 teammates
- Large plans (10+ tasks) might group by domain
- File-heavy overlap triggers worktree isolation

### Hybrid worktree strategy

Default to shared worktree (simpler, lower overhead). If the lead detects file overlap between task groups, it auto-creates separate worktrees for conflicting teammates and merges results at the end. This avoids unnecessary complexity for the common case while preventing merge conflicts for the complex case.

## Key Decisions

1. **Start with `/soleur:work`** -- it has the strongest parallelization signal (discrete plan tasks) and existing infrastructure (TodoWrite, incremental commits). Other commands can adopt the patterns in v2.

2. **Auto-detect + confirm** -- analyze plan dependency graph, suggest Agent Teams if 3+ independent tasks exist, require user confirmation before spawning.

3. **3-tier execution: Agent Teams > Subagent fan-out > Sequential** -- user can choose their cost/capability tradeoff when prompted.

4. **Lead decides task grouping** -- the lead agent dynamically groups tasks based on dependency graph, file overlap, and domain boundaries.

5. **Hybrid worktree strategy** -- shared worktree by default, per-teammate worktrees when file overlap is detected between task groups.

6. **v2 generalization targets** -- `/soleur:review` (stateful multi-lens review), `/resolve_parallel` (dependent comment resolution), potential new `/soleur:build` command for greenfield projects.

## Dogfooding Strategy

Use Agent Teams to implement this feature itself. Execute the implementation plan using manually-spawned Agent Teams to validate assumptions and gather real-world feedback:
- Task grouping effectiveness
- Shared vs. per-teammate worktree friction
- Consent UX feel
- Error handling needs
- Commit coordination challenges

Learnings from dogfooding feed directly into the final implementation.

## Open Questions

- **Max teammates cap?** Should we limit the maximum number of teammates to prevent runaway costs? (e.g., cap at 6 teammates)
- **Progress reporting** -- how should the lead surface teammate progress to the user? Inline updates, summary on completion, or real-time dashboard?
- **Error handling** -- if a teammate fails mid-task, should the lead retry, reassign to another teammate, or fall back to sequential for that task?
- **Commit strategy** -- should each teammate commit independently, or should only the lead commit after merging all work?
