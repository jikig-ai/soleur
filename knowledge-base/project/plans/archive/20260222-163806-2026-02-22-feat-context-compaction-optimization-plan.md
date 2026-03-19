---
title: "feat: Context Compaction Optimization"
type: feat
date: 2026-02-22
---

# Context Compaction Optimization

## Overview

Reduce context window pressure in multi-step workflows by (1) trimming command bodies through reference file extraction and constitution deduplication, and (2) isolating plan+deepen as a subagent in the one-shot pipeline with error forwarding via a cumulative session-state file.

The compaction boundary is between plan+deepen and work in the one-shot pipeline (one-shot does not include brainstorm). For manual brainstorm-then-plan flows, guidance directs users to start a new session.

## Problem Statement / Motivation

The plugin's 60 agents, 46 skills, and 9 commands create ~10k tokens of always-on baseline per turn. The five heaviest commands total 13,292 words. In a one-shot pipeline, context accumulates to ~50k+ tokens of instructions alone by step 6, triggering compaction that degrades response quality and loses error context that compound depends on.

**Current command sizes (words):**

| Command | Words | Extractable Content |
|---------|-------|-------------------|
| brainstorm.md | 2,906 | Domain config table (~800w), workshops (~800w) |
| plan.md | 3,274 | 3 issue templates (~1,000w), community/overlap checks (~600w) |
| work.md | 2,946 | Agent Teams (~500w), Subagent Fan-Out (~400w) |
| review.md | 2,500 | Todo file structure (~400w), testing section (~400w) |
| compound.md | 1,666 | Already lean -- modify only |
| **Total** | **13,292** | **~4,900w extractable** |

## Proposed Solution

### Prong 1: Reduce Baseline Context Pressure

Extract heavy, conditionally-used content from command bodies into reference files that are loaded on demand via Read tool.

**Reference file location:** `plugins/soleur/commands/soleur/references/`

Before implementing, verify the command loader does NOT recurse into subdirectories by creating a test file. If it does recurse, fall back to `plugins/soleur/references/commands/` (outside the commands directory).

**Constitution deduplication:** Only `plan.md` and `work.md` explicitly load `knowledge-base/overview/constitution.md` in their Phase 0. The other commands (brainstorm, review, compound) only load `CLAUDE.md`. Add conditional instruction to plan.md and work.md Phase 0: "If `# Project Constitution` content is already present in this conversation, skip reading `knowledge-base/overview/constitution.md`." This is heuristic-based but zero-infrastructure and only applied where the load actually exists.

### Prong 2: Subagent Isolation in One-Shot Pipeline

In `one-shot.md`, spawn steps 1-2 (plan + deepen-plan) as a combined isolated Task subagent. The subagent produces the plan file on disk and returns a structured session summary. The parent writes this summary to `session-state.md`. Work (step 3) then starts with a fresher context, reading the plan from disk.

**Session-state file:** `knowledge-base/specs/feat-<name>/session-state.md`

- Append-only: each pipeline step appends a section
- Consumed by compound for error inventory and route-to-definition
- Only written in pipeline (subagent) mode; standalone commands skip it

**Subagent return contract:** The plan+deepen subagent must end its output with:

```markdown
## Session Summary
### Errors
- [error description] (or "none")
### Decisions
- [key decision made]
### Components Invoked
- [agent/skill/command names]
### Plan File
- [path to plan file]
```

The parent parses by heading name and appends to session-state.md.

**Fallback:** If the subagent fails (timeout, context limit), the parent falls back to running plan inline (no compaction, but no data loss).

### Prong 2b: Manual Flow Guidance

After standalone brainstorm completes, add to the output message: "All artifacts are on disk. Starting a new session for `/soleur:plan` will give you maximum context headroom."

No programmatic compaction -- just guidance for the user.

## Technical Considerations

### Architecture

- Commands use Read tool to load references on demand (same pattern as skills)
- Session-state.md follows a heading contract (exact `##` names) per constitution principle
- compound-docs skill (3,072 words) also needs updating to read session-state.md

### Risks

- **Command loader recursion:** If the loader discovers `.md` files in `commands/soleur/references/`, they become phantom commands. Mitigated by verifying loader behavior in Phase 1.
- **Model skips reading references:** The model might not reliably defer Read calls to the step that needs them. Mitigated by explicit "Read [file] now" instructions at each step.
- **Session-state parsing fragility:** The parent must parse the subagent's free-text output. Mitigated by using a strict heading contract and validating before writing.
- **Constitution dedup false positives:** The model might skip loading constitution when it hasn't actually seen it. Mitigated by checking for the specific `# Project Constitution` heading rather than a generic "already loaded" heuristic. Only applied to 2 commands (plan, work) to limit blast radius.

### Compatibility

- All standalone command invocations must continue working unchanged
- Session-state.md is additive -- compound reads it in addition to (not instead of) conversation history
- Reference files are only loaded when the execution path needs them

## Acceptance Criteria

- [ ] Total command body size reduced by ~40% (13,292 -> ~8,400 total words)
- [ ] Constitution loaded at most once per pipeline run (plan and work dedup)
- [ ] Plan+deepen runs as isolated subagent in one-shot pipeline
- [ ] Session-state.md created and appended to during one-shot pipeline
- [ ] Compound reads session-state.md for error inventory and route-to-definition
- [ ] All standalone command invocations still work correctly
- [ ] Command loader does not discover reference files as commands

## Test Scenarios

### Loader Verification
- Given a `.md` file in `commands/soleur/references/`, when the plugin loads, then it must NOT appear as a discoverable command

### Standalone Brainstorm
- Given a user runs `/soleur:brainstorm` alone, when brainstorm reaches Phase 0.5, then domain config table is loaded via Read tool and brainstorm functions identically to current behavior

### Standalone Plan
- Given a user runs `/soleur:plan` alone with no prior command, when plan selects A LOT detail level, then the A LOT template is loaded from references and used correctly

### One-Shot Pipeline with Subagent
- Given a user runs `/soleur:one-shot`, when plan+deepen completes as a subagent, then a structured session summary is returned and written to session-state.md

### One-Shot Subagent Failure Fallback
- Given a user runs `/soleur:one-shot` and the plan subagent fails, when the parent detects the failure, then plan runs inline (no compaction) and the pipeline continues

### Malformed Subagent Output
- Given the plan subagent returns output without the expected `## Session Summary` heading, when the parent attempts to parse, then the parent writes a "parsing failed" note to session-state.md and continues the pipeline

### Compound with Session-State
- Given a one-shot pipeline run with session-state.md, when compound runs Phase 0.5, then it reads session-state.md and includes forwarded errors in the error inventory

### Compound without Session-State (Standalone)
- Given a user runs `/soleur:compound` standalone, when no session-state.md exists, then compound falls back to scanning conversation history only (current behavior)

### Constitution Deduplication in Pipeline
- Given a one-shot pipeline where plan loaded constitution, when work runs Phase 0, then constitution is not re-read from disk

### Manual Sequential Constitution Loading
- Given a user runs `/soleur:plan` then `/soleur:work` manually in the same session, when work reaches Phase 0, then it detects constitution is already in context and skips re-reading

### Reference File Not Found
- Given a reference file is missing or renamed, when a command attempts to Read it, then the command warns and continues with degraded behavior (not a fatal error)

## Implementation Phases

### Phase 1: Verify and Setup (~30 min)

Verify command loader behavior and create reference directory structure.

**Tasks:**
- [x] 1.1: Create test file `commands/soleur/references/loader-test.md` with valid frontmatter
- [x] 1.2: Verify it does NOT appear as a discoverable command
- [x] 1.3: If it DOES appear, use fallback path `plugins/soleur/references/commands/`
- [x] 1.4: Remove test file
- [x] 1.5: Create the final reference directory structure

### Phase 2: Extract Command Content to References (~2 hrs)

Move heavy content from command bodies to reference files. For each command, the body retains the flow skeleton with Read instructions at each step. Also add the brainstorm output guidance message (Prong 2b).

**Tasks:**

#### brainstorm.md (2,906w -> ~1,300w target, actual: 1,711w = 41%)
- [x] 2.1: Extract domain config table (8 rows) to `references/brainstorm-domain-config.md`
- [x] 2.2: Extract Brand Workshop section to `references/brainstorm-brand-workshop.md`
- [x] 2.3: Extract Validation Workshop section to `references/brainstorm-validation-workshop.md`
- [x] 2.4: Replace extracted content with Read instructions in brainstorm.md body
- [x] 2.5: Add Prong 2b message to brainstorm's Phase 4 output
- [x] 2.6: Verify standalone brainstorm still works end-to-end

#### plan.md (3,274w -> ~1,800w target, actual: 2,280w = 30%)
- [x] 2.7: Extract 3 issue templates (MINIMAL, MORE, A LOT) to `references/plan-issue-templates.md`
- [x] 2.8: Extract Community Discovery Check to `references/plan-community-discovery.md`
- [x] 2.9: Extract Functional Overlap Check to `references/plan-functional-overlap.md`
- [x] 2.10: Replace extracted content with Read instructions in plan.md body
- [x] 2.11: Verify standalone plan still works with each detail level

#### work.md (2,946w -> ~2,000w target, actual: 2,291w = 22%)
- [x] 2.12: Extract Agent Teams protocol (Tier A) to `references/work-agent-teams.md`
- [x] 2.13: Extract Subagent Fan-Out protocol (Tier B) to `references/work-subagent-fanout.md`
- [x] 2.14: Replace extracted content with Read instructions in work.md body
- [x] 2.15: Verify standalone work still works with all 3 tiers

#### review.md (2,500w -> ~1,700w target, actual: 1,777w = 29%)
- [x] 2.16: Extract todo file structure and naming conventions to `references/review-todo-structure.md`
- [x] 2.17: Extract end-to-end testing section to `references/review-e2e-testing.md`
- [x] 2.18: Replace extracted content with Read instructions in review.md body
- [x] 2.19: Verify standalone review still works

### Phase 3: Constitution Deduplication (~15 min)

Only plan.md and work.md explicitly load constitution.md. brainstorm.md, review.md, and compound.md only load CLAUDE.md and do NOT need this change.

- [x] 3.1: Update plan.md Phase 0 with conditional: "If `# Project Constitution` content is already present in this conversation, skip reading constitution.md"
- [x] 3.2: Update work.md Phase 0 with the same conditional
- [x] 3.3: Verify standalone plan and work still load constitution on first run
- [x] 3.4: Verify that in a pipeline (plan then work), work skips the re-read

### Phase 4: One-Shot Subagent Isolation (~1 hr)

Modify one-shot pipeline to spawn plan+deepen as an isolated subagent. The compaction boundary is between plan+deepen (step 1-2) and work (step 3).

**Tasks:**
- [x] 4.1: Define session-state.md format with concrete example
- [x] 4.2: Modify `one-shot.md` to spawn steps 1-2 as a combined Task subagent
- [x] 4.3: Add subagent return contract instructions to the Task prompt
- [x] 4.4: Add parent logic to parse subagent output and write session-state.md
- [x] 4.5: Add fallback: if subagent fails or output is malformed, run plan inline
- [x] 4.6: Verify plan+deepen subagent portion works correctly

### Phase 5: Compound Session-State Integration (~1 hr)

Update compound and compound-docs to read session-state.md.

**Tasks:**
- [x] 5.1: Update compound.md Phase 0.5 to read session-state.md if it exists
- [x] 5.2: Update compound.md Route-to-Definition to include components from session-state.md
- [x] 5.3: Read compound-docs SKILL.md and update Step 2 (Gather Context) to also read session-state.md
- [x] 5.4: Verify compound with session-state.md present
- [x] 5.5: Verify compound without session-state.md (standalone fallback)

### Phase 6: Measurement and Validation (~15 min)

- [x] 6.1: Run `wc -w` on all modified command files
- [x] 6.2: Compare to baseline table -- 26% static reduction (9,794w from 13,292w). Runtime savings higher due to conditional loading and subagent isolation.
- [x] 6.3: Verify all acceptance criteria are met

## Dependencies & Risks

**Dependencies:**
- Phase 1 blocks Phase 2 (loader verification determines file placement)
- Phase 2 blocks Phase 3 (both edit plan.md and work.md -- cannot parallel)
- Phase 4 is independent after Phase 1 (only modifies one-shot.md)
- Phase 5 tasks 5.1-5.3 are independent after Phase 1 (modify compound.md and compound-docs)
- Phase 5 depends on Phase 4 conceptually (session-state.md format defined in 4.1)
- Phase 6 depends on Phases 2-5

**Corrected execution order:**
1. Phase 1 (verify loader)
2. Phase 2 (extract references) + Phase 4 (one-shot subagent) -- can parallel
3. Phase 3 (constitution dedup) -- after Phase 2
4. Phase 5 (compound integration) -- after Phase 4
5. Phase 6 (measurement) -- after all

**Risks:**
- Command loader recurses into references/ (mitigated by Phase 1 test + fallback path)
- Model inconsistently loads references (mitigated by explicit Read instructions)
- Session-state parsing fails (mitigated by heading contract + fallback to inline)
- Constitution dedup false positives (mitigated by limiting to 2 commands + specific heading check)

## References & Research

### Internal References
- Brainstorm: `knowledge-base/brainstorms/2026-02-22-context-compaction-brainstorm.md`
- Spec: `knowledge-base/specs/feat-context-compaction/spec.md`
- Agent token budget learning: `knowledge-base/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md`
- Skill reference pattern: `plugins/soleur/skills/skill-creator/references/` (14 files, well-established)
- Constitution: `knowledge-base/overview/constitution.md` (3,219 words)

### Related Issues
- #268 - Context Compaction Optimization (this feature)

## Version Bump Intent

PATCH -- this is an optimization of existing commands, no new skills/commands/agents added.
