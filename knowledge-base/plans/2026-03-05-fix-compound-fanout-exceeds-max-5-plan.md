---
title: "fix: compound parallel fan-out exceeds max-5 subagent limit"
type: fix
date: 2026-03-05
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 4 (Proposed Solution, Acceptance Criteria, Test Scenarios, Files to Modify)
**Research sources:** 5 learnings, constitution.md, compound SKILL.md, compound-capture SKILL.md

### Key Improvements

1. Confirmed compound-capture SKILL.md has zero references to subagent names -- no cascading changes needed
2. Clarified that constitution.md line 201 uses generic language (no specific count) -- no edit required
3. Added edge case: Deviation Analyst line 125 text becomes accurate post-fix (was aspirational with 6 agents)
4. Added verification that merged responsibilities preserve compound-capture's category mapping dependency

### New Considerations Discovered

- The Deviation Analyst paragraph (line 125) says "to respect the max-5 parallel subagent limit" -- this statement is currently false (6 agents exist) but becomes true after the fix; no text change needed
- compound-capture SKILL.md Step 6 references "category mapping defined in yaml-schema.md" independently of the parallel subagents -- the capture skill is unaffected because it runs its own sequential flow
- The Success Output block has exactly 6 check-mark lines under "Primary Subagent Results:" and must be reduced to 5 with a merged description line

# fix: compound parallel fan-out exceeds max-5 subagent limit

## Overview

Compound's `## Execution Strategy: Parallel Subagents` section in `plugins/soleur/skills/compound/SKILL.md` declares 6 numbered parallel subagents plus an optional 7th, violating the constitution.md rule at line 148:

> Parallel subagent fan-out requires explicit user consent, bounded agent count (max 5), and lead-coordinated commits

Discovered during SpecFlow analysis for #397. The Deviation Analyst (#416) was already made sequential (Phase 1.5) to avoid bumping to 7, but the core fan-out was never reduced from 6 to 5. This fix closes the gap.

## Problem Statement

The 6 parallel subagents are:

1. **Context Analyzer** -- extracts problem type, component, symptoms; returns YAML frontmatter skeleton
2. **Solution Extractor** -- identifies root cause; returns solution content block
3. **Related Docs Finder** -- searches knowledge-base/learnings/; returns links and relationships
4. **Prevention Strategist** -- develops prevention strategies and test cases
5. **Category Classifier** -- determines optimal category and suggests filename
6. **Documentation Writer** -- assembles complete markdown file, validates YAML, creates file

Subagent #7 (Specialized Agent Invocation) is already post-documentation and optional, so it is out of scope.

The fix must reduce the parallel count from 6 to 5 without losing functionality.

## Proposed Solution: Merge Category Classifier into Documentation Writer

Merge subagent #5 (Category Classifier) into subagent #6 (Documentation Writer). Rationale:

- **Natural coupling.** The Documentation Writer already "creates the file in correct location" per SKILL.md line 113. Determining the category and filename is a prerequisite of file creation, not an independent analysis task. The classifier's output (path + filename) is consumed exclusively by the writer.
- **Minimal scope.** Category Classifier is the smallest subagent (3 bullets: determine category, validate against schema, suggest filename). Its work is trivially absorbed into the writer's existing "validates YAML frontmatter" and "creates the file in correct location" responsibilities.
- **No loss of parallelism.** All other subagents remain independent and parallel. The merged writer gains one extra responsibility (category classification) that does not increase its wall-clock time meaningfully.

### Research Insights

**Prior art confirms this pattern.** The project has three documented cases of plan review reducing scope by merging components:
- `2026-03-03-deviation-analyst-scope-reduction.md`: 7+ files reduced to ~60 lines in 1 file (60% reduction)
- `2026-02-22-plan-review-collapses-agent-architecture.md`: 3 agents collapsed to 23 lines of inline instructions
- `2026-02-09-parallel-subagent-fan-out-in-work-command.md`: established the "max 5 groups" pattern that compound adopted

**Merge direction is validated by data flow.** Category Classifier's 3 outputs (category, schema validation, filename) flow exclusively to Documentation Writer. No other subagent consumes these outputs. This is a classic producer-consumer merge where the producer has exactly one consumer.

**No cascading impact.** Verified that `compound-capture/SKILL.md` (725 lines) has zero references to any parallel subagent names (Context Analyzer, Solution Extractor, etc.). The capture skill determines category independently via its own Step 6 using `yaml-schema.md` references. The parallel subagent names exist only in `compound/SKILL.md`.

### Why not the other options?

- **Option 2 (update constitution limit to 6):** Changing the limit to accommodate one skill sets a precedent. The max-5 limit exists for resource bounding and cognitive load reasons. Increasing it weakens the guardrail for all future parallel fan-outs.
- **Option 3 (make one subagent sequential):** Making any subagent sequential adds wall-clock time without reducing complexity. The Deviation Analyst (#416) already demonstrated that sequential is the right choice for phases that depend on parallel output, but Category Classifier does not depend on other subagents' output -- it just determines a path. Merging is cleaner than sequentializing.

## Non-Goals

- Changing the Deviation Analyst (Phase 1.5) execution model -- it is already correctly sequential
- Modifying the optional subagent #7 (Specialized Agent Invocation) -- it runs post-documentation
- Adding enforcement tooling (hooks, CI checks) for the max-5 limit -- that is a separate concern
- Refactoring compound-capture SKILL.md -- the capture skill does not define the parallel fan-out

## Acceptance Criteria

- [x] `plugins/soleur/skills/compound/SKILL.md` lists exactly 5 numbered parallel subagents (not 6)
- [x] The merged subagent (#5 Documentation Writer) includes all 6 responsibilities: determines optimal category, validates category against schema, suggests filename, assembles complete markdown file, validates YAML frontmatter, creates file in correct location
- [x] `knowledge-base/overview/constitution.md` line 201 requires NO changes -- verified it uses generic language ("the pipeline's parallel subagent limit") not a hardcoded count
- [x] The Success Output example in compound SKILL.md shows exactly 5 Primary Subagent Results with the Documentation Writer line covering both classification and assembly
- [x] No changes to `plugins/soleur/skills/compound-capture/SKILL.md` -- verified zero references to parallel subagent names
- [x] Phase 1.5 Deviation Analyst text (line 125) requires NO changes -- "to respect the max-5 parallel subagent limit" becomes accurate after the fix
- [ ] Compound runs correctly end-to-end after the change

## Test Scenarios

- Given compound SKILL.md is updated, when counting `### N.` headers under `## Execution Strategy: Parallel Subagents`, then exactly 5 numbered parallel subagents exist
- Given the merged Documentation Writer section, when reading its responsibilities, then it includes "determines optimal category," "validates category against schema," and "suggests filename" (formerly Category Classifier bullets)
- Given the Success Output block, when reading `Primary Subagent Results:`, then exactly 5 check-mark lines appear with the Documentation Writer line showing both classification and documentation results
- Given a session that invokes compound, when the parallel fan-out executes, then no more than 5 Task tool calls are issued simultaneously
- Given compound-capture SKILL.md, when searching for any parallel subagent name (Context Analyzer, Solution Extractor, etc.), then zero matches are found (confirms no cascading impact)
- Given constitution.md line 201, when reading the sequential-phase principle, then no hardcoded subagent count appears (generic language preserved)
- Given the Optional Specialized Agent Invocation section, when checking its header number, then it is numbered `### 6.` (renumbered from 7)

## Files to Modify

### `plugins/soleur/skills/compound/SKILL.md` (single file, all changes)

**Edit 1: Remove Category Classifier section (lines 100-106)**

Delete the entire `### 5. **Category Classifier** (Parallel)` block including its 3 bullet points.

**Edit 2: Renumber and merge Documentation Writer (lines 107-113)**

Change `### 6. **Documentation Writer** (Parallel)` to `### 5. **Documentation Writer** (Parallel)` and add the 3 former Category Classifier bullets before the existing bullets. The merged section should read:

```markdown
### 5. **Documentation Writer** (Parallel)

- Determines optimal `knowledge-base/learnings/` category
- Validates category against schema
- Suggests filename based on slug
- Assembles complete markdown file
- Validates YAML frontmatter
- Formats content for readability
- Creates the file in correct location
```

**Edit 3: Renumber Specialized Agent Invocation (line 114)**

Change `### 7. **Optional: Specialized Agent Invocation**` to `### 6.`

**Edit 4: Verify Phase 1.5 text (line 125) -- NO CHANGE NEEDED**

Line 125 reads: "This phase runs sequentially (not as a parallel subagent) to respect the max-5 parallel subagent limit." This becomes accurate after the fix (currently aspirational with 6 agents). Leave unchanged.

**Edit 5: Update Success Output (lines 343-348)**

Replace the 6-line Primary Subagent Results block with 5 lines. Remove the Category Classifier line and update the Documentation Writer line to reflect merged responsibilities:

```text
Primary Subagent Results:
  [check] Context Analyzer: Identified performance_issue in brief_system
  [check] Solution Extractor: Extracted 3 code fixes
  [check] Related Docs Finder: Found 2 related issues
  [check] Prevention Strategist: Generated test cases
  [check] Documentation Writer: Classified to performance-issues/, created complete markdown
```

### Files NOT modified (verified)

- `plugins/soleur/skills/compound-capture/SKILL.md` -- zero references to parallel subagent names
- `knowledge-base/overview/constitution.md` -- line 148 (max-5 rule) and line 201 (sequential principle) both use generic language, no hardcoded counts to update

## Context

- Constitution rule: `knowledge-base/overview/constitution.md` line 148
- Compound skill: `plugins/soleur/skills/compound/SKILL.md` lines 68-122
- Prior art: #416 (Deviation Analyst made sequential to respect limit)
- Learning: `knowledge-base/learnings/2026-03-03-deviation-analyst-scope-reduction.md`
- Learning: `knowledge-base/learnings/2026-02-09-parallel-subagent-fan-out-in-work-command.md`

## References

- Issue: #423
- PR #416: feat: add Deviation Analyst Phase 1.5 to compound skill
- Related: #397 (SpecFlow analysis that discovered the violation)
