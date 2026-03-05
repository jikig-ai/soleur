---
title: "fix: compound parallel fan-out exceeds max-5 subagent limit"
type: fix
date: 2026-03-05
semver: patch
---

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

### Why not the other options?

- **Option 2 (update constitution limit to 6):** Changing the limit to accommodate one skill sets a precedent. The max-5 limit exists for resource bounding and cognitive load reasons. Increasing it weakens the guardrail for all future parallel fan-outs.
- **Option 3 (make one subagent sequential):** Making any subagent sequential adds wall-clock time without reducing complexity. The Deviation Analyst (#416) already demonstrated that sequential is the right choice for phases that depend on parallel output, but Category Classifier does not depend on other subagents' output -- it just determines a path. Merging is cleaner than sequentializing.

## Non-Goals

- Changing the Deviation Analyst (Phase 1.5) execution model -- it is already correctly sequential
- Modifying the optional subagent #7 (Specialized Agent Invocation) -- it runs post-documentation
- Adding enforcement tooling (hooks, CI checks) for the max-5 limit -- that is a separate concern
- Refactoring compound-capture SKILL.md -- the capture skill does not define the parallel fan-out

## Acceptance Criteria

- [ ] `plugins/soleur/skills/compound/SKILL.md` lists exactly 5 numbered parallel subagents (not 6)
- [ ] The merged subagent (#5 Documentation Writer) includes category classification, schema validation, filename suggestion, file assembly, YAML validation, and file creation
- [ ] `knowledge-base/overview/constitution.md` line 201 (the existing principle about sequential phases) still references the correct subagent limit
- [ ] The Success Output example in compound SKILL.md reflects the merged subagent (5 results, not 6)
- [ ] No changes to compound-capture SKILL.md (it has its own sequential flow)
- [ ] Compound runs correctly end-to-end after the change

## Test Scenarios

- Given compound SKILL.md is updated, when counting `### N.` headers under `## Execution Strategy: Parallel Subagents`, then exactly 5 numbered parallel subagents exist
- Given the merged Documentation Writer section, when reading its responsibilities, then it includes "determines optimal category," "validates category against schema," and "suggests filename" (formerly Category Classifier bullets)
- Given the Success Output block, when reading `Primary Subagent Results:`, then exactly 5 lines appear with the merged writer showing both classification and documentation results
- Given a session that invokes compound, when the parallel fan-out executes, then no more than 5 Task tool calls are issued simultaneously

## Files to Modify

### `plugins/soleur/skills/compound/SKILL.md`

1. Remove `### 5. **Category Classifier** (Parallel)` section (lines 100-106)
2. Renumber `### 6. **Documentation Writer** (Parallel)` to `### 5. **Documentation Writer** (Parallel)`
3. Add Category Classifier's responsibilities to the merged Documentation Writer:
   - "Determines optimal `knowledge-base/learnings/` category"
   - "Validates category against schema"
   - "Suggests filename based on slug"
4. Renumber `### 7. **Optional: Specialized Agent Invocation**` to `### 6.`
5. Update the `## Phase 1.5: Deviation Analyst (Sequential)` paragraph if it references "6 parallel subagents"
6. Update the Success Output block to show 5 Primary Subagent Results, not 6

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
