---
title: "feat: parallel agent lifecycle orchestration (Tier 0)"
type: feat
date: 2026-03-03
---

# feat: Parallel Agent Lifecycle Orchestration (Tier 0)

## Overview

Add Tier 0 (Lifecycle Parallelism) to the work skill's execution model. Tier 0 generates an interface contract from the plan, spawns two parallel agents (code and tests), and integrates their output through test-fix-loop. This compresses the feature lifecycle by running code implementation and acceptance test writing concurrently under ATDD discipline. Documentation is written sequentially after integration.

## Problem Statement / Motivation

The current feature lifecycle runs sequentially: plan, work (implement), review, compound, ship. The work skill's existing parallelism (Tier A/B) parallelizes within implementation tasks but does not parallelize across lifecycle concerns. Code and test writing are independent workstreams that share only a specification -- they can run concurrently if given a shared interface contract.

## Proposed Solution

### Architecture

Tier 0 inserts before the existing Tier A/B/C cascade in work Phase 2:

```
                     Plan / Spec
                         |
                         v
        +-----------------------------------+
        |  Contract Generation              |
        |  Coordinator reads plan ->        |
        |  generates file scopes +          |
        |  public interface signatures      |
        +----------------+------------------+
                         |
               +---------+---------+
               v                   v
          +---------+         +---------+
          | Agent 1 |         | Agent 2 |
          | Code    |         | Tests   |
          | (impl)  |         | (ATDD)  |
          +---------+         +---------+
               |                   |
               +---------+---------+
                         |
                         v
        +-----------------------------------+
        |  Integration                      |
        |  Coordinator commits all output   |
        |  -> test-fix-loop until GREEN     |
        |  -> docs written sequentially     |
        +-----------------------------------+
```

### Tier Selection

Tier 0 is a **pre-check before the existing independence analysis**. The coordinator reads the plan and applies a single judgment: "Does this plan have distinct code and test workstreams that can be assigned to separate agents with non-overlapping file scopes?"

```
Plan loaded
  -> If plan has independent code + test workstreams: offer Tier 0
     -> If declined or ineligible: proceed to existing cascade
  -> Existing cascade: 3+ independent tasks? -> Tier A -> B -> C
```

No keyword scanning or category detection algorithm. The LLM already reads the plan -- let it decide.

**Pipeline mode:** When invoked from one-shot with a plan file, auto-select Tier 0 if eligible (same pattern as Tier B auto-select today). No interactive prompt.

### Interface Contract

The coordinator generates a markdown document at `knowledge-base/project/specs/feat-<name>/interface-contract.md` with two sections:

```markdown
## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | (list of source files, package.json, config files) |
| Agent 2 (Tests) | (list of test files) |

## Public Interfaces

(function/class signatures with parameter types, return types, error types)
```

**Contract generation source:** The plan file and spec (if available). The coordinator reads the plan's task descriptions, acceptance criteria, and references to derive signatures.

The plan itself provides all other context (motivation, data flow, examples). The contract adds only what agents need to avoid collision: file ownership and interface signatures.

**Version triad** (`plugin.json`, `CHANGELOG.md`, root `README.md`) is **deferred to Ship** -- neither agent touches these files.

### Agent Prompts

Each agent receives via Task tool:

1. **BRANCH:** Current feature branch name
2. **WORKING DIRECTORY:** Absolute worktree path
3. **INTERFACE CONTRACT:** Full contract document
4. **YOUR FILES:** Explicit file list from the contract
5. **INSTRUCTIONS:** Role-specific instructions (below)
6. **CONSTRAINTS:** "Do NOT commit. Do NOT modify files outside YOUR FILES list. Do NOT use the Bash tool. Do NOT use WebFetch or WebSearch. Do NOT run git commands. Run `pwd` before every file write to verify you are in the worktree."

**Agent 1 (Code) instructions:**
- Implement the feature to satisfy the public interfaces in the contract
- Follow existing codebase patterns (read neighboring files for style)
- Add dependencies to package.json if needed
- Do NOT write test files -- Agent 2 handles all tests

**Agent 2 (Tests) instructions:**
- Write acceptance tests from the interface contract (ATDD RED phase)
- Tests must validate the public interfaces listed in the contract
- Use Given/When/Then format per constitution
- Do NOT read source files -- write tests from the contract only
- Use the project's test framework (auto-detect from package.json/Cargo.toml/etc.)

### Integration Phase

After both agents return:

1. **Stage and commit:** `git add . && git commit -m "feat: parallel agent output (pre-integration)"`
   - The coordinator MUST commit before invoking test-fix-loop. test-fix-loop requires a clean working tree and aborts if uncommitted changes exist.
2. **Run test suite:** Execute the project's test command.
3. **If tests pass:** Write documentation sequentially. Proceed to Phase 3 (Quality Check).
4. **If tests fail:** Invoke `skill: soleur:test-fix-loop` to iterate until GREEN.
5. **If test-fix-loop cannot converge:** Flag as contract-test mismatch. Present the failing tests and implementation to the user for manual resolution.
6. **After GREEN:** Write documentation sequentially (architecture docs, feature docs). Docs are fast and benefit from seeing the final implementation.

### Partial Agent Failure

One rule: **If any agent fails, keep the successful agent's output and complete the remaining work sequentially via Tier C.** No per-agent recovery matrix.

## Technical Considerations

### Architecture Impacts

- **Work skill SKILL.md:** Modified Phase 2 section 1 with new Tier 0 pre-check and reference file loading instruction
- **New reference file:** `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` containing the full Tier 0 protocol
- **One-shot:** No changes. Invokes work with plan file path as before.
- **Ship:** No changes. Version triad handling is deferred to Ship's Phase 5.
- **Review/Compound:** No changes. They operate on the committed output regardless of which tier produced it.

### Key Constraints from Learnings

- **Subagents do NOT commit** -- coordinator commits after integration (parallel-agents-on-main-cause-conflicts)
- **Explicit file scoping** -- each agent gets exact file list to prevent conflicts (parallel-subagent-css-class-mismatch)
- **No halt language** -- reference file must not use "stop", "announce", "tell the user" (and-stop-halt-language-breaks-pipeline)
- **Session-state.md for errors** -- write agent failures to session-state.md for compound to pick up (context-compaction-command-optimization)
- **Contract heading-level format** -- use exact `##` names (brand-guide-contract-and-inline-validation)
- **Restrict subagent tools via instructions** -- agents instructed not to use Bash/WebFetch/WebSearch (multi-agent-cascade-orchestration-checklist). Tool restriction is instruction-level only; Claude Code's Task tool does not support per-agent tool whitelisting.
- **pwd verification** -- agents must run `pwd` before every file write to verify worktree location (worktree-edit-discipline)
- **Commit before test-fix-loop** -- test-fix-loop requires clean working tree; coordinator must commit agent output first (test-fix-loop SKILL.md precondition)

### Filesystem Race Condition Mitigation

Two agents writing to the same worktree simultaneously is safe because file scopes are non-overlapping. The contract assigns every file to exactly one agent. Agents are instructed not to use the Bash tool or run git commands -- the coordinator handles all git operations post-integration.

### Known Issue: test-fix-loop stash in worktrees

test-fix-loop uses `git stash` internally as a rollback mechanism. The constitution forbids stash in worktrees. This is a pre-existing conflict not introduced by this plan. Track separately as a GitHub issue.

## Acceptance Criteria

- [ ] Work skill offers Tier 0 when plan has independent code + test workstreams
- [ ] Interface contract generated before agents spawn with file scopes and signatures
- [ ] Two agents execute in parallel (concurrent Task tool invocations in a single message)
- [ ] No agent commits directly -- coordinator commits after integration
- [ ] Test failures trigger test-fix-loop delegation
- [ ] Partial agent failure triggers graceful fallback to Tier C sequential
- [ ] One-shot pipeline works unchanged (pipeline mode auto-selects Tier 0 when eligible)
- [ ] Existing Tier A/B/C cascade unaffected when Tier 0 is not selected

## Test Scenarios

- Given a plan with independent code and test workstreams, when work enters Phase 2, then Tier 0 is offered
- Given pipeline mode with an eligible plan, when Tier 0 runs, then no interactive prompts are shown
- Given Tier 0 is declined, when the cascade continues, then Tier A/B/C behave identically to before
- Given both agents complete successfully and tests pass, then coordinator commits and writes docs sequentially
- Given both agents complete but tests fail, when test-fix-loop is invoked, then it iterates until GREEN or reports non-convergence
- Given one agent fails, when the coordinator detects failure, then the successful agent's output is kept and remaining work completes via Tier C
- Given a plan without distinct test workstream, when Tier 0 check runs, then it falls through to the A/B/C cascade

## Dependencies and Risks

### Dependencies

- test-fix-loop skill must accept a working tree with a fresh commit (current behavior -- it requires clean tree, which is satisfied after coordinator commits)
- Task tool must support 2+ concurrent invocations in a single message (existing behavior -- Tier B already spawns up to 5)

### Risks

| Risk | Mitigation |
|------|------------|
| Contract-test mismatch (test agent misinterprets contract) | test-fix-loop non-convergence is the signal. Coordinator flags for manual review. |
| Agent reads another agent's files despite instructions | Instruction-level constraint. v2 could add filesystem isolation. |
| test-fix-loop stash conflicts in worktree | Pre-existing issue. Track as separate GH issue. |

## Implementation Plan

### Phase 1: Reference File (core protocol document)

**Create:** `plugins/soleur/skills/work/references/work-lifecycle-parallel.md`

Contents: The full Tier 0 protocol following the existing reference file pattern:
- Step 01: Offer (interactive) / Auto-select (pipeline)
- Step 02: Generate interface contract (file scopes + signatures)
- Step 03: Spawn 2 parallel agents (code + tests)
- Step 04: Collect results, commit all output
- Step 05: Run test-fix-loop until GREEN
- Step 06: Write docs sequentially, proceed to Phase 3

### Phase 2: Work Skill Modification

**Modify:** `plugins/soleur/skills/work/SKILL.md`

Changes:
1. Add Tier 0 pre-check BEFORE the existing independence analysis in Phase 2 section 1
2. Single judgment instruction: "Does this plan have independent code + test workstreams with non-overlapping file scopes?"
3. Add reference file loading instruction: `**Read plugins/soleur/skills/work/references/work-lifecycle-parallel.md now**`
4. Update pipeline mode override to include Tier 0 auto-select
5. Add fallthrough from Tier 0 to existing Tier A

### Phase 3: Version Bump and Compliance

**Modify (version triad):**
- `plugins/soleur/.claude-plugin/plugin.json` -- MINOR bump
- `plugins/soleur/CHANGELOG.md` -- Added entry
- `plugins/soleur/README.md` -- Verify counts

**Verify:** One-shot pipeline still works end-to-end by reading the SKILL.md and confirming the control flow is unbroken.

## References and Research

### Internal References

- Work skill: `plugins/soleur/skills/work/SKILL.md`
- Tier A protocol: `plugins/soleur/skills/work/references/work-agent-teams.md`
- Tier B protocol: `plugins/soleur/skills/work/references/work-subagent-fanout.md`
- test-fix-loop: `plugins/soleur/skills/test-fix-loop/SKILL.md`
- One-shot: `plugins/soleur/skills/one-shot/SKILL.md`
- Ship: `plugins/soleur/skills/ship/SKILL.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-03-parallel-agent-lifecycle-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-parallel-agent-lifecycle/spec.md`

### Learnings Applied

- `2026-02-17-parallel-agents-on-main-cause-conflicts.md` -- isolation mandatory
- `2026-02-13-parallel-subagent-css-class-mismatch.md` -- explicit reference lists
- `2026-02-09-parallel-subagent-fan-out-in-work-command.md` -- bounded fan-out pattern
- `2026-03-02-multi-agent-cascade-orchestration-checklist.md` -- pre-flight checklist
- `2026-02-12-brand-guide-contract-and-inline-validation.md` -- heading-level contracts
- `2026-03-03-and-stop-halt-language-breaks-pipeline.md` -- no halt language
- `2026-02-22-context-compaction-command-optimization.md` -- session-state.md pattern
- `2026-02-18-skill-cannot-invoke-skill.md` -- skill invocation hierarchy

### Related Issues

- #396 -- Original feature request
- #408 -- Draft PR
