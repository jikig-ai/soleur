# Parallel Agent Feature Lifecycle Orchestration

**Date:** 2026-03-03
**Issue:** #396
**Status:** Brainstorm complete, ready for planning
**Branch:** feat-parallel-agent-lifecycle

## What We're Building

A new execution tier (Tier 0: Lifecycle Parallelism) in the `work` skill that spawns three parallel agents — code, tests, and docs — working from a shared interface contract. This compresses the feature lifecycle by running independent workstreams concurrently rather than sequentially.

### The Core Flow

1. **Phase 0: Interface Contract Generation** — The coordinator reads the plan/spec and generates a medium-fidelity interface contract: function signatures, module file paths, data flow between modules, and one usage example per public function. This takes ~1-2 minutes and becomes the shared source of truth for all three agents.

2. **Phase 1: Parallel Execution** — Three agents start simultaneously from the contract:
   - **Agent 1 (Code):** Implements the feature against the interface contract
   - **Agent 2 (Tests):** Writes acceptance tests against the contract (ATDD RED phase — tests do NOT depend on code existing)
   - **Agent 3 (Docs):** Updates CHANGELOG, README, version references, and documentation

3. **Phase 2: Integration** — The coordinator merges all three agents' work into the same branch, then delegates to `test-fix-loop` to iterate until all tests pass (GREEN). Final commit after integration.

## Why This Approach

### ATDD Enables True Parallelism

The original issue (#396) assumed tests depend on code (traditional TDD). In ATDD, acceptance tests are written from the spec, not the implementation. This flips the dependency: tests and code can be written simultaneously from the same contract.

The **hybrid interface contract** is the key innovation. Without it, parallel agents risk interface mismatch (Agent 1 names a function `processOrder` while Agent 2 tests `handleOrder`). The contract is cheap to produce but eliminates this class of failure entirely.

### Tier 0 in Work Skill (Not a New Skill)

The work skill already owns execution tier selection (Tier A: Agent Teams, Tier B: Subagent Fan-Out, Tier C: Sequential). Adding Tier 0 is architecturally consistent:

- One-shot, ship, review, compound — nothing changes
- Work internally decides whether the plan warrants Tier 0/A/B/C
- New reference file (`work-lifecycle-parallel.md`) follows the existing pattern

### test-fix-loop for Integration Failures

When tests + code merge and tests fail, the existing `test-fix-loop` skill handles the RED → GREEN iteration. No new retry mechanism needed.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where it lives | Tier 0 in work skill | Extends existing tier pattern; minimal blast radius to other skills |
| ATDD vs traditional TDD | ATDD — tests from contract, not code | Enables true 3-way parallelism; tests don't wait for implementation |
| Interface contract fidelity | Medium (signatures + data flow + examples) | Minimal is too thin for meaningful tests; rich over-specifies edge cases that belong in RED/GREEN iteration |
| Integration fix strategy | Delegate to `test-fix-loop` | Already proven, handles iteration + termination conditions |
| Agent commit model | Coordinator-only commits | Consistent with all existing parallel patterns (Tier A, B, review, resolve-parallel) |
| Worktree model | All agents share one worktree | Git prohibits two worktrees on the same branch; multi-branch merge is fragile |

## Open Questions

1. **Tier selection heuristic:** How does the work skill decide when Tier 0 is appropriate vs Tier A/B/C? Possible signals: task count, task categories (code/test/doc tasks detected in plan), explicit user flag.

2. **Agent 3 scope vs Ship skill:** The ship skill already handles version bumps and CHANGELOG. How much should Agent 3 do upfront vs deferring to ship? Likely: Agent 3 writes CHANGELOG entries and docs; ship handles the version triad validation.

3. **Contract format:** Should the interface contract be a structured file (JSON schema, TypeScript types) or a markdown document? Structured is machine-parseable but harder to generate; markdown is natural for LLM agents.

4. **Failure modes:** What happens when one agent fails but others succeed? Options: retry the failed agent, abort all, or proceed with partial results and flag gaps.

5. **File conflict prevention:** How do we prevent Agent 1 and Agent 2 from touching the same file? Explicit file scoping in the contract (Agent 1 owns `src/`, Agent 2 owns `test/`, Agent 3 owns `docs/` and root markdown files)?

## Constraints from Learnings

- **Subagents do NOT commit** — coordinator commits after integration (learning: parallel-agents-on-main-cause-conflicts)
- **Bounded fan-out** — max 5 groups, explicit user consent (learning: parallel-subagent-fan-out)
- **Explicit file scoping** — each agent gets an explicit file list to prevent conflicts (learning: parallel-subagent-css-class-mismatch)
- **pwd before every write** — verify worktree location (learning: worktree-edit-discipline)
- **MCP paths are absolute** — MCP tools resolve from repo root, not shell CWD (learning: playwright-screenshots-land-in-main-repo)
- **No stash in worktrees** — commit WIP, never stash (learning: worktree-loss-stash-merge-pop)
- **Version bump intent, not number** — specify MINOR/PATCH, not exact version (learning: parallel-feature-version-conflicts)
