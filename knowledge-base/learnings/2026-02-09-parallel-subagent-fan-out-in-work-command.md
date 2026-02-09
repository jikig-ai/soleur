# Learning: Parallel subagent fan-out pattern in /soleur:work

## Problem

`/soleur:work` processed plan tasks sequentially even when 3+ independent tasks (no `blockedBy` dependencies, no file overlap) could run in parallel. Other plugin commands already had proven parallel patterns (`/soleur:review` with 9+ agents, `/resolve_parallel` with N agents), but `/soleur:work` had no parallel path.

## Solution

Added a conditional "Parallel Execution (optional)" block to `work.md` Phase 2, inserted before the existing sequential task loop. Four steps:

1. **Analyze independence** -- read TaskList, identify tasks with no `blockedBy` and no file overlap
2. **Decide execution mode** -- if 3+ independent tasks, ask user; if < 3, skip to sequential
3. **Group and spawn** -- cluster into max 5 groups, spawn one Task general-purpose agent per group in a single message with multiple tool calls
4. **Collect and integrate** -- wait for all, fall back to sequential for failures, run tests, lead commits

Key design: subagents do NOT commit. The lead commits after collecting all work and running integration tests. This avoids git coordination complexity entirely.

## Key Insight

Retrofitting parallelism into a sequential workflow requires four elements: (1) autonomous dependency analysis (blockedBy + AI reading), (2) explicit user consent before expensive operations, (3) bounded fan-out (max N agents), (4) lead-coordinated commits (no distributed git). The pattern generalizes to any command where independent work units can be detected from task metadata.

## Secondary Insight: Worktree path resolution gap

When invoking `/soleur:work` with a plan file path, the command initially looked in the main repo root rather than the worktree directory where the file actually existed. Phase 0 of `/work` should detect the active worktree and resolve paths relative to it. This is a known gap for future improvement.

## Tags

category: implementation-patterns
module: soleur-plugin
tags: parallel-execution, fan-out-pattern, task-tool, subagent-coordination, worktree-awareness
