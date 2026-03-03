# Spec: Parallel Agent Feature Lifecycle Orchestration

**Issue:** #396
**Date:** 2026-03-03
**Status:** Draft

## Problem Statement

The current feature lifecycle in the `one-shot` skill runs sequentially: plan → work → review → compound → ship. The `work` skill's internal parallelism (Tier A/B) operates within the implementation phase but does not parallelize across lifecycle concerns (code, tests, docs). This leaves time on the table when independent workstreams could overlap.

## Goals

- **G1:** Enable true 3-way parallelism for code implementation, acceptance test writing, and documentation updates within a single feature lifecycle.
- **G2:** Preserve ATDD discipline — acceptance tests are written from a shared contract, not reverse-engineered from implementation code.
- **G3:** Integrate into the existing work skill as Tier 0 without breaking one-shot, ship, review, or compound.
- **G4:** Reuse existing infrastructure (`test-fix-loop`, subagent fan-out patterns, coordinator-commits-only model).

## Non-Goals

- Multi-worktree orchestration (deferred — git branch constraint makes this fragile)
- Replacing the existing Tier A/B/C execution tiers (Tier 0 is additive)
- Automating tier selection without user consent (explicit opt-in for Tier 0)
- Full API spec generation (medium-fidelity contract is sufficient)

## Functional Requirements

- **FR1:** The work skill must support a new Tier 0 execution mode that spawns three parallel agents (code, tests, docs) from a shared interface contract.
- **FR2:** The coordinator must generate a medium-fidelity interface contract from the plan containing: function/class signatures, module file paths, data flow between modules, and one usage example per public function.
- **FR3:** Each agent must receive an explicit file scope (Agent 1: source files, Agent 2: test files, Agent 3: docs/changelog/version files) to prevent write conflicts.
- **FR4:** Agents must NOT commit. The coordinator integrates all work and commits after the test-fix-loop confirms GREEN.
- **FR5:** The integration phase must delegate to `test-fix-loop` for RED → GREEN iteration when acceptance tests fail against the merged code.
- **FR6:** The tier selection in work Phase 2 must detect when Tier 0 is applicable (tasks span code/test/doc concerns) and present it as an option alongside Tier A/B/C.

## Technical Requirements

- **TR1:** New reference file `work-lifecycle-parallel.md` in `skills/work/references/` documenting the Tier 0 protocol (consistent with `work-agent-teams.md` and `work-subagent-fanout.md`).
- **TR2:** Interface contract document written to a temporary file in the worktree (e.g., `.claude/interface-contract.md`) for all three agents to read.
- **TR3:** Bounded fan-out — three agents maximum for Tier 0, within the existing max-5 subagent limit.
- **TR4:** All agents share the same worktree. No multi-worktree or multi-branch coordination.
- **TR5:** Coordinator must run `pwd` verification before every file write (worktree discipline).
- **TR6:** MCP tool paths must be absolute when invoked from within the worktree.

## Acceptance Criteria

- [ ] Work skill offers Tier 0 when plan contains code + test + docs tasks
- [ ] Interface contract is generated before agents spawn
- [ ] Three agents execute in parallel (verified by concurrent Task tool invocations)
- [ ] No agent commits directly — only coordinator commits
- [ ] Test failures trigger test-fix-loop delegation
- [ ] One-shot pipeline works unchanged when Tier 0 is selected
- [ ] Ship skill handles version bump correctly after Tier 0 execution
