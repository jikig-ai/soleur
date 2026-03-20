# Spec: Parallel Agent Feature Lifecycle Orchestration

**Issue:** #396
**Date:** 2026-03-03
**Status:** Draft [Updated 2026-03-03 -- simplified per plan review]

## Problem Statement

The current feature lifecycle in the `one-shot` skill runs sequentially: plan, work, review, compound, ship. The `work` skill's internal parallelism (Tier A/B) operates within the implementation phase but does not parallelize across lifecycle concerns. Code and test writing are independent workstreams that can overlap when given a shared interface contract.

## Goals

- **G1:** Enable 2-way parallelism for code implementation and acceptance test writing within a single feature lifecycle. Documentation written sequentially after integration.
- **G2:** Preserve ATDD discipline -- acceptance tests are written from a shared contract, not reverse-engineered from implementation code.
- **G3:** Integrate into the existing work skill as Tier 0 without breaking one-shot, ship, review, or compound.
- **G4:** Reuse existing infrastructure (`test-fix-loop`, subagent fan-out patterns, coordinator-commits-only model).

## Non-Goals

- Multi-worktree orchestration (deferred -- git branch constraint makes this fragile)
- Replacing the existing Tier A/B/C execution tiers (Tier 0 is additive)
- Automating tier selection without user consent (explicit opt-in for Tier 0)
- Parallel docs agent (deferred to v2 -- docs are fast to write sequentially)
- Full API spec generation (minimal contract with file scopes + signatures is sufficient)

## Functional Requirements

- **FR1:** The work skill must support a new Tier 0 execution mode that spawns two parallel agents (code and tests) from a shared interface contract.
- **FR2:** The coordinator must generate a minimal interface contract containing: file scope assignments (which agent owns which files) and public interface signatures (function/class signatures with types).
- **FR3:** Each agent must receive an explicit file scope. Agent 1: source files. Agent 2: test files. No overlap.
- **FR4:** Agents must NOT commit. The coordinator commits all output, then delegates to `test-fix-loop` for RED-to-GREEN iteration.
- **FR5:** After integration passes (GREEN), documentation is written sequentially by the coordinator.
- **FR6:** The tier selection in work Phase 2 must use LLM judgment ("Does this plan have independent code + test workstreams?") as a pre-check before the existing A/B/C cascade.

## Technical Requirements

- **TR1:** New reference file `work-lifecycle-parallel.md` in `skills/work/references/` documenting the Tier 0 protocol (consistent with `work-agent-teams.md` and `work-subagent-fanout.md`).
- **TR2:** Interface contract document written to `knowledge-base/project/specs/feat-<name>/interface-contract.md` for both agents to read.
- **TR3:** Bounded fan-out -- two agents for Tier 0, within the existing max-5 subagent limit.
- **TR4:** All agents share the same worktree. No multi-worktree or multi-branch coordination.
- **TR5:** Agents must run `pwd` verification before every file write (worktree discipline).
- **TR6:** Agent tool restriction is instruction-level: agents instructed not to use Bash, WebFetch, WebSearch, or git commands.

## Acceptance Criteria

- [ ] Work skill offers Tier 0 when plan has independent code + test workstreams
- [ ] Interface contract generated before agents spawn with file scopes and signatures
- [ ] Two agents execute in parallel (concurrent Task tool invocations)
- [ ] No agent commits directly -- coordinator commits after integration
- [ ] Test failures trigger test-fix-loop delegation
- [ ] One-shot pipeline works unchanged when Tier 0 is selected
- [ ] Ship skill handles version bump correctly after Tier 0 execution
- [ ] Existing Tier A/B/C cascade unaffected when Tier 0 is not selected
