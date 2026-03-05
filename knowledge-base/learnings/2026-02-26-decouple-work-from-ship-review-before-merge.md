---
title: Decouple work from ship to enable review before merge
date: 2026-02-26
category: workflow-patterns
tags: [architecture, work, one-shot, ship]
---

# Learning: Decouple work from ship to enable review before merge

## Problem
One-shot pipeline ran review (step 4) after work/ship had already merged the PR and cleaned up the worktree. Review findings were unactionable. The manual workflow (brainstorm -> plan -> work) had the same issue: work auto-delegated to ship, giving no opportunity to run review between implementation and merge.

## Solution
Work's Phase 4 behavior depends on who invoked it:

- **Via one-shot**: Hand off control immediately. One-shot orchestrates: work -> review -> resolve -> compound -> ship.
- **Directly by user**: Continue automatically through compound -> ship. There is no orchestrator to hand off to, so stopping dead violates "Workflow Completion is Not Task Completion" (the PR never gets created).

## Key Insight
The decoupling principle is correct for orchestrated pipelines (one-shot), but must not create a dead end for direct invocations. When no orchestrator exists, the skill must self-complete. The heuristic: "hand off if there's a caller; finish if there isn't."

[Updated 2026-03-02: Phase 4 now branches on invocation context instead of always stopping.]

## Tags
category: architecture
module: work, one-shot, ship
