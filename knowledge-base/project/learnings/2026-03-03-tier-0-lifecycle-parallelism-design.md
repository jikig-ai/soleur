---
title: "Tier 0 Lifecycle Parallelism Design"
category: architecture
date: 2026-03-03
tags: [parallel-agents, atdd, work-skill, tier-0, interface-contract]
---

# Learning: Tier 0 Lifecycle Parallelism Design

## Problem

The `/soleur:work` skill's execution tiers (A: Agent Teams, B: Subagent Fan-Out, C: Sequential) all operate at the *task* level -- they parallelize independent tasks within a plan. But the most common bottleneck is not task independence; it is the sequential lifecycle itself. In a typical feature, the code agent writes implementation, then writes tests, then writes docs -- serially. The test-writing phase cannot start until the code phase finishes, even though the test author does not actually need the source code. They need the *interface* -- what functions exist, what they accept, what they return, and what errors they throw.

This sequential dependency model meant that a 30-minute feature took 30 minutes wall-clock, even when a second agent could have been writing tests in parallel from minute zero.

## Solution

Tier 0 (Lifecycle Parallelism) sits above the existing task-level tiers and operates at the *phase* level. It splits the RED-GREEN lifecycle itself into two parallel streams:

1. **Generate an interface contract** -- a minimal markdown document with two sections: File Scopes (which agent owns which files, with zero overlap) and Public Interfaces (function/class signatures with parameter types, return types, error types). The contract is derived from the plan and committed before agents spawn.

2. **Spawn two parallel agents from the contract:**
   - Agent 1 (Code) implements the feature to satisfy the public interfaces.
   - Agent 2 (Tests) writes acceptance tests *from the contract alone* (ATDD RED phase), without reading source files.

3. **Coordinator integrates** -- waits for both agents, commits their combined output, then runs `test-fix-loop` until GREEN. Docs are written sequentially after GREEN because they benefit from seeing the final integrated implementation.

Tier selection uses LLM judgment ("Does this plan have distinct code and test workstreams with non-overlapping file scopes?") rather than a keyword-scanning algorithm. The model already reads the plan; adding a brittle heuristic on top adds complexity without accuracy.

## Key Insight

**ATDD flips the dependency arrow that makes code-then-tests sequential.** In traditional TDD, tests import the module under test -- they depend on the source code existing. In ATDD, tests depend on the *interface contract*, not the implementation. This is the same dependency inversion that enables API-first development: the consumer (tests) and the provider (code) both depend on the contract, not on each other. Once you see this, lifecycle parallelism becomes a trivial consequence of contract-first design.

Three non-obvious design constraints emerged during implementation:

1. **The contract must be minimal.** An early draft included data flow diagrams, error handling matrices, and example payloads. This created speculative work -- agents would implement details that the plan never called for, guided by over-specified contract sections. Two sections (File Scopes + Public Interfaces) turned out to be the minimum viable contract: enough to prevent file collisions and ensure test-code compatibility, without prescribing implementation details.

2. **Coordinator-commits-only is mandatory, not optional.** Prior learnings (`2026-02-17-parallel-agents-on-main-cause-conflicts.md`) established that parallel agents should not commit independently. Tier 0 makes this structural: agents are explicitly constrained from running git commands, and the coordinator commits all output in a single pre-integration commit. This also satisfies `test-fix-loop`'s requirement for a clean working tree.

3. **One failure rule replaces a failure matrix.** The initial design included a 2x2 matrix (code succeeds/fails x tests succeed/fail) with four different recovery paths. Plan review collapsed this to a single rule: "Keep what worked, finish the rest via Tier C." The failed agent's workstream becomes sequential tasks. No elaborate recovery orchestration needed.

## Related Learnings

- `2026-02-09-parallel-subagent-fan-out-in-work-command.md` -- established the lead-coordinated-commits pattern that Tier 0 builds on
- `2026-02-13-parallel-subagent-css-class-mismatch.md` -- demonstrated that parallel agents need explicit shared references (class name lists, interface contracts) rather than full file content
- `2026-02-06-parallel-plan-review-catches-overengineering.md` -- the same review process that caught overengineering in 3 prior features caught it again here (3 agents reduced to 2, failure matrix reduced to one rule, category detection algorithm replaced by LLM judgment)
- `2026-03-02-multi-agent-cascade-orchestration-checklist.md` -- silent failure modes in multi-agent spawning; Tier 0 addresses these by constraining agent tool access (no Bash, no git, no WebFetch) and requiring explicit file scope ownership

## Session Errors

None detected.

## Tags

category: architecture
module: work-skill
