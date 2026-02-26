# Learning: Decouple work from ship to enable review before merge

## Problem
One-shot pipeline ran review (step 4) after work/ship had already merged the PR and cleaned up the worktree. Review findings were unactionable. The manual workflow (brainstorm -> plan -> work) had the same issue: work auto-delegated to ship, giving no opportunity to run review between implementation and merge.

## Solution
Changed work's Phase 4 from auto-delegating to ship to a handoff. Work now does implementation only (Phases 0-3) and announces "Implementation complete. Next steps: review -> compound -> ship." The caller (one-shot or user) controls the lifecycle. One-shot steps restructured: work -> review -> resolve -> compound -> ship.

## Key Insight
Skills that auto-invoke downstream skills create tight coupling that removes control points. When a pipeline needs to insert steps between implementation and merge (review, resolve, compound), the implementation skill must hand off control rather than driving through to merge. The principle: implementation skills should implement, shipping skills should ship, and the orchestrator decides the sequence.

## Tags
category: architecture
module: work, one-shot, ship
