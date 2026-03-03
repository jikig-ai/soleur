---
title: "feat: parallel agent lifecycle orchestration (Tier 0)"
type: feat
date: 2026-03-03
---

# feat: Parallel Agent Lifecycle Orchestration (Tier 0)

## Overview

Add Tier 0 (Lifecycle Parallelism) to the work skill's execution model. Tier 0 generates an interface contract from the plan, spawns three parallel agents (code, tests, docs), and integrates their output through test-fix-loop. This compresses the feature lifecycle by running independent workstreams concurrently under ATDD discipline.

## Problem Statement / Motivation

The current feature lifecycle runs sequentially: plan, work (implement), review, compound, ship. The work skill's existing parallelism (Tier A/B) parallelizes within implementation tasks but does not parallelize across lifecycle concerns. Code, test, and documentation writing are independent workstreams that share only a specification -- they can run concurrently if given a shared interface contract.

## Proposed Solution

### Architecture

Tier 0 inserts before the existing Tier A/B/C cascade in work Phase 2. It uses a three-phase execution model:

```
                     Plan / Spec
                         |
                         v
        +-----------------------------------+
        |  Phase 0: Interface Contract      |
        |  Coordinator reads plan ->        |
        |  generates contract (signatures,  |
        |  data flow, examples, file paths) |
        +----------------+------------------+
                         |
            +------------+------------+
            v            v            v
       +---------+  +---------+  +---------+
       | Agent 1 |  | Agent 2 |  | Agent 3 |
       | Code    |  | Tests   |  | Docs    |
       | (impl)  |  | (ATDD)  |  | (prose) |
       +---------+  +---------+  +---------+
            |            |            |
            +------------+------------+
                         |
                         v
        +-----------------------------------+
        |  Phase 2: Integration             |
        |  Coordinator commits all output   |
        |  -> test-fix-loop until GREEN     |
        |  -> final commit                  |
        +-----------------------------------+
```

### Tier Selection Heuristic

Tier 0 is a **pre-check before the existing independence analysis**. The decision tree becomes:

```
Plan loaded
  -> Analyze task categories (not just independence)
  -> If tasks span 3 categories (code + test + doc): offer Tier 0
     -> If declined or ineligible: proceed to existing cascade
  -> Existing cascade: 3+ independent tasks? -> Tier A -> B -> C
```

**Category detection:** The coordinator scans TaskList for signals:
- **Code tasks:** Tasks referencing source file paths, "implement", "create", "add"
- **Test tasks:** Tasks referencing test files, "test", "verify", "validate"
- **Doc tasks:** Tasks referencing docs, README, architecture docs, "document", "update docs"

If all three categories are present, Tier 0 is offered. Otherwise, fall through to the existing A/B/C cascade unchanged.

**Pipeline mode:** When invoked from one-shot with a plan file, auto-select Tier 0 if eligible (same pattern as Tier B auto-select today). No interactive prompt.

### Interface Contract

The coordinator generates a markdown document at `knowledge-base/specs/feat-<name>/interface-contract.md` with this heading-level contract:

```markdown
## Module Map
(file paths for each new/modified module, organized by agent scope)

## Agent 1: Source Files
(list of files Agent 1 may create/modify)

## Agent 2: Test Files
(list of files Agent 2 may create/modify)

## Agent 3: Documentation Files
(list of files Agent 3 may create/modify)

## Public Interfaces
(function/class signatures with parameter types, return types, error types)

## Data Flow
(which modules call which, dependency direction)

## Usage Examples
(one example per public function showing input -> output)
```

**Contract generation source:** The plan file and spec (if available). The coordinator reads the plan's task descriptions, acceptance criteria, and references to derive signatures.

**Shared file ownership:** Cross-cutting files are assigned exclusively:
- `package.json`, `bun.lockb`, `tsconfig.json` -> Agent 1 (code)
- `knowledge-base/`, architecture docs -> Agent 3 (docs)
- Version triad (`plugin.json`, `CHANGELOG.md`, root `README.md`) -> **deferred to Ship** (not any agent)
- Config files not listed in any agent scope -> Coordinator handles post-integration

### Agent Prompts

Each agent receives via Task tool:

1. **BRANCH:** Current feature branch name
2. **WORKING DIRECTORY:** Absolute worktree path
3. **INTERFACE CONTRACT:** Full contract document
4. **YOUR FILES:** Explicit file list from the contract (the agent's scope section)
5. **INSTRUCTIONS:** Role-specific instructions (below)
6. **CONSTRAINTS:** "Do NOT commit. Do NOT modify files outside YOUR FILES list. Do NOT run git commands."

**Agent 1 (Code) instructions:**
- Implement the feature to satisfy the public interfaces in the contract
- Follow existing codebase patterns (read neighboring files for style)
- Add dependencies to package.json if needed
- Write unit tests alongside implementation (co-located in test/ per constitution)

**Agent 2 (Tests) instructions:**
- Write acceptance tests from the interface contract (ATDD RED phase)
- Tests must validate the public interfaces, data flow, and usage examples
- Use Given/When/Then format per constitution
- Do NOT read source files -- write tests from the contract only
- Use the project's test framework (auto-detect from package.json/Cargo.toml/etc.)

**Agent 3 (Docs) instructions:**
- Write/update documentation that describes the feature's purpose and usage
- Update architecture docs if the feature changes module boundaries
- Do NOT touch version files (plugin.json, CHANGELOG.md, README counts) -- Ship handles those
- Reference the interface contract for accurate function names and data flow

### Integration Phase

After all three agents return:

1. **Verify file scoping:** Check that no agent wrote outside its assigned files. If violations found, discard the violating output and flag to user.
2. **Stage and commit:** `git add . && git commit -m "feat: parallel agent output (pre-integration)"`
3. **Run test suite:** Execute the project's test command.
4. **If tests pass:** Done. Proceed to Phase 3 (Quality Check).
5. **If tests fail:** Invoke `skill: soleur:test-fix-loop` to iterate until GREEN.
6. **If test-fix-loop cannot converge:** Flag as contract-test mismatch. Present the failing tests and implementation to the user for manual resolution.

### Partial Agent Failure

| Failure | Action |
|---------|--------|
| Code agent fails | Keep tests (contract-derived, still valid). Discard docs. Fall back to Tier C sequential for code tasks. Re-run docs agent after code is complete. |
| Test agent fails | Keep code. Fall back to Tier C sequential for test tasks. Docs remain valid. |
| Docs agent fails | Keep code and tests. Run integration. Write docs sequentially after GREEN. |
| Multiple agents fail | Fall back to Tier C sequential for all remaining tasks. |

## Technical Considerations

### Architecture Impacts

- **Work skill SKILL.md:** Modified Phase 2 section 1 with new Tier 0 pre-check and reference file loading instruction
- **New reference file:** `plugins/soleur/skills/work/references/work-lifecycle-parallelism.md` containing the full Tier 0 protocol
- **One-shot:** No changes. Invokes work with plan file path as before.
- **Ship:** No changes. Version triad handling is deferred to Ship's Phase 5.
- **Review/Compound:** No changes. They operate on the committed output regardless of which tier produced it.

### Key Constraints from Learnings

- **Subagents do NOT commit** -- coordinator commits after integration (parallel-agents-on-main-cause-conflicts)
- **Explicit file scoping** -- each agent gets exact file list to prevent conflicts (parallel-subagent-css-class-mismatch)
- **No halt language** -- reference file must not use "stop", "announce", "tell the user" (and-stop-halt-language-breaks-pipeline)
- **Session-state.md for errors** -- write agent failures to session-state.md for compound to pick up (context-compaction-command-optimization)
- **Contract heading-level format** -- use exact `##` names, required/optional flags (brand-guide-contract-and-inline-validation)
- **Restrict subagent tools** -- agents get Read/Write/Edit/Glob/Grep only, not Bash/WebFetch (multi-agent-cascade-orchestration-checklist)

### Filesystem Race Condition Mitigation

Three agents writing to the same worktree simultaneously is safe IF file scopes are non-overlapping. The contract explicitly assigns every file to exactly one agent. The coordinator verifies no file appears in multiple agent scopes before spawning.

Agents are instructed not to run `git` commands, `git add`, or `git status` -- the coordinator handles all git operations post-integration.

## Acceptance Criteria

- [ ] Work skill offers Tier 0 when plan tasks span code + test + docs categories
- [ ] Interface contract generated at `knowledge-base/specs/feat-<name>/interface-contract.md` before agents spawn
- [ ] Three agents execute in parallel (concurrent Task tool invocations in a single message)
- [ ] No agent commits directly -- coordinator commits after integration
- [ ] File scope violations detected and flagged before committing
- [ ] Test failures trigger test-fix-loop delegation
- [ ] Partial agent failure triggers graceful fallback to sequential
- [ ] One-shot pipeline works unchanged (pipeline mode auto-selects Tier 0 when eligible)
- [ ] Ship handles version bump correctly (Agent 3 does not touch version triad)
- [ ] Existing Tier A/B/C cascade unaffected when Tier 0 is not selected

## Test Scenarios

- Given a plan with code, test, and docs tasks, when work enters Phase 2, then Tier 0 is offered as an option
- Given pipeline mode with an eligible plan, when Tier 0 runs, then no interactive prompts are shown
- Given Tier 0 is declined, when the cascade continues, then Tier A/B/C behave identically to before
- Given all three agents complete successfully, when tests pass, then coordinator creates a single commit
- Given all three agents complete but tests fail, when test-fix-loop is invoked, then it iterates until GREEN or reports non-convergence
- Given Agent 1 fails, when the coordinator detects failure, then tests are preserved and code falls back to sequential
- Given an agent writes outside its file scope, when the coordinator checks, then the violation is flagged and the output discarded
- Given a plan with only code and test tasks (no docs), when Tier 0 heuristic runs, then it falls through to the A/B/C cascade
- Given a plan with 2 tasks total (below min threshold), when Tier 0 heuristic runs, then it falls through to Tier C

## Dependencies and Risks

### Dependencies

- test-fix-loop skill must accept a working tree with a fresh commit (current behavior -- it requires clean tree, which is satisfied after coordinator commits)
- Task tool must support 3+ concurrent invocations in a single message (existing behavior -- Tier B already spawns up to 5)

### Risks

| Risk | Mitigation |
|------|------------|
| Contract-test mismatch (test agent misinterprets contract) | test-fix-loop non-convergence is the signal. Coordinator flags for manual review. |
| Agent reads another agent's files despite instructions | Instruction-level constraint. v2 could add filesystem isolation. |
| Large plans overflow contract generation context | Contract generation runs in the main context, not a subagent. If the plan is too large, the coordinator summarizes before generating. |

## Implementation Plan

### Phase 1: Reference File (core protocol document)

**Create:** `plugins/soleur/skills/work/references/work-lifecycle-parallelism.md`

Contents: The full Tier 0 protocol following the existing reference file pattern:
- Step 01: Offer (interactive) / Auto-select (pipeline)
- Step 02: Generate interface contract
- Step 03: Spawn 3 parallel agents
- Step 04: Collect results and verify file scoping
- Step 05: Commit and run test-fix-loop
- Step 06: Handle failures / proceed to Phase 3

### Phase 2: Work Skill Modification

**Modify:** `plugins/soleur/skills/work/SKILL.md`

Changes:
1. Add Tier 0 pre-check BEFORE the existing independence analysis in Phase 2 section 1
2. Add category detection logic (code/test/doc task scanning)
3. Add reference file loading instruction: `**Read plugins/soleur/skills/work/references/work-lifecycle-parallelism.md now**`
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
- Brainstorm: `knowledge-base/brainstorms/2026-03-03-parallel-agent-lifecycle-brainstorm.md`
- Spec: `knowledge-base/specs/feat-parallel-agent-lifecycle/spec.md`

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
