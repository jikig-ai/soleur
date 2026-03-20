---
title: Add Engineering Skills from claude-code-agents
type: feat
date: 2026-02-09
---

# Add Engineering Skills from claude-code-agents

[Updated 2026-02-09 after plan review by DHH, Kieran, and Simplicity reviewers]

## Overview

Adopt 6 software engineering methodology components from [andlaf-ak/claude-code-agents](https://github.com/andlaf-ak/claude-code-agents) into the soleur plugin: 4 review agents, 2 workflow skills, plus a minor enhancement to the existing brainstorming skill.

## Problem Statement

The soleur plugin excels at workflow orchestration (brainstorm, plan, work, review, ship) but lacks methodology-driven engineering skills. A developer using soleur has no built-in way to get a Farley-scored test review, guided ATDD development, or DDD design analysis. The claude-code-agents repo has these capabilities, well-structured and language-agnostic.

## Proposed Solution

Convert source agents into soleur format, trimming prompts to match existing conventions (~50-90 lines of prompt body). Drop items that overlap with existing agents.

### What Changed After Review

| Original | Revised | Reason |
|----------|---------|--------|
| 6 agents | 4 agents | Dropped `clean-coder` (overlaps with code-simplicity-reviewer, pattern-recognition-specialist, architecture-strategist). Merged `code-smell-detector` + `refactoring-expert` into one `code-quality-analyst`. |
| 3 skills | 2 skills | Dropped `problem-analyst` as standalone skill. Merging its "pure analysis" mode into existing brainstorming skill (~5 lines). |
| 500-800 line targets (spec) / 120-300 (plan) | ~50-90 lines prompt body | Aligned with existing review agent convention. Existing agents range 45-90 lines. |

### Differentiation from Existing Agents

| New Agent | Closest Existing | Boundary |
|-----------|-----------------|----------|
| `code-quality-analyst` | `pattern-recognition-specialist` | pattern-recognition-specialist does broad anti-pattern scanning and naming conventions. code-quality-analyst uses Fowler's structured 5-phase framework with severity scoring, smell-to-refactoring mappings, and a formal report format. |
| `test-design-reviewer` | None | Completely unique. No existing agent scores test quality. |
| `legacy-code-expert` | None | Completely unique. No existing agent covers Feathers' techniques. |
| `ddd-architect` | `architecture-strategist` | architecture-strategist reviews general SOLID/coupling/layering. ddd-architect applies Evans' strategic DDD: bounded contexts, context maps, aggregate design, domain events. |

### File Inventory

**4 New Agents** in `plugins/soleur/agents/review/`:

| File | Source | Estimated Lines |
|------|--------|----------------|
| `code-quality-analyst.md` | code-smell-detector.md + refactoring-expert.md | ~80 (merged, trimmed) |
| `test-design-reviewer.md` | test-design-reviewer.md | ~70 (reformat frontmatter) |
| `legacy-code-expert.md` | legacy-code-expert.md | ~70 (reformat frontmatter) |
| `ddd-architect.md` | ddd-architect-agent.md | ~70 (reformat, drop knowledge base) |

**2 New Skills** in `plugins/soleur/skills/`:

| Directory | Source | Estimated Lines |
|-----------|--------|----------------|
| `atdd-developer/SKILL.md` | atdd-developer.md (53 lines) | ~70 (reformat to skill frontmatter) |
| `user-story-writer/SKILL.md` | user-story-writer.md (85 lines) | ~90 (reformat to skill frontmatter) |

**1 Modified Skill:**

| File | Change |
|------|--------|
| `plugins/soleur/skills/brainstorming/SKILL.md` | Add ~5 lines: routing option for pure problem analysis mode |

**3 Updated Files** (version bump):

| File | Change |
|------|--------|
| `.claude-plugin/plugin.json` | version: 1.8.0 -> 1.9.0 |
| `CHANGELOG.md` | Add [1.9.0] entry |
| `README.md` | Update agent/skill counts and tables |

## Technical Approach

### Format Conventions

- **Agent descriptions:** Start with "Use this agent when..." (second person imperative). Include 2-3 `<example>` blocks with `<commentary>` tags. Single-line escaped string with `\\n`.
- **Skill descriptions:** Start with "This skill should be used when..." (third person). Include trigger keywords.
- **Agent model:** `model: inherit`
- **Prompt body style:** Imperative form. No second person ("you should"). Match existing agent length (~50-90 lines).

### Agent Conversion Pattern

1. Rewrite YAML frontmatter to soleur format (name, description with examples, model: inherit)
2. Trim prompt body to ~50-90 lines. Drop all domain knowledge Opus 4.6 already has. Keep only: role constraints, methodology framing, output format, scoring models, unique workflows
3. No `references/` directories for skills -- all methodology context fits in SKILL.md

### Core Value Preserved Per Agent

- **code-quality-analyst:** 5-phase detection framework + severity model + smell-to-refactoring mappings + report structure (merged from two source agents)
- **test-design-reviewer:** Farley Score formula + weighted rubric + grade bands + table output
- **legacy-code-expert:** Feathers' 24 techniques + seam taxonomy (object/preprocessing/link) + 4-step approach
- **ddd-architect:** Strategic-first mandate + context mapping + 5-step process + Mermaid diagram output

### What Gets Dropped

- `clean-coder` agent entirely (covered by existing code-simplicity-reviewer, pattern-recognition-specialist, architecture-strategist)
- `problem-analyst` as standalone skill (merged into brainstorming as routing option)
- `ddd-expert-knowledge-base.md` (1,447 lines) -- Opus 4.6 knows DDD
- Embedded encyclopedias from code-smell-detector (smell catalog) and refactoring-expert (66 techniques)
- SOLID/GRASP principle definitions (model knows these)
- Language-specific bash detection commands

### Integration Decisions

- **/soleur:review integration:** Deferred to a future issue. Users invoke new agents directly via Task(). Per spec NG4.
- **Chaining:** Moot -- code-smell-detector and refactoring-expert are now merged into one agent.
- **problem-analyst:** Merged into brainstorming skill as a routing option for pure analysis mode.

## Acceptance Criteria

- [ ] 4 agent .md files created in `plugins/soleur/agents/review/`
- [ ] 2 skill directories created in `plugins/soleur/skills/` with SKILL.md each
- [ ] Brainstorming skill updated with problem analysis routing (~5 lines)
- [ ] All agents have proper YAML frontmatter (name, description with examples, model: inherit)
- [ ] All skills have proper YAML frontmatter (name, third-person description)
- [ ] Agent prompt bodies are 50-90 lines (matching existing convention)
- [ ] Version bumped to 1.9.0 in `.claude-plugin/plugin.json`
- [ ] CHANGELOG.md updated with [1.9.0] entry
- [ ] README.md updated with new agent/skill counts and tables
- [ ] `bun test` passes
- [ ] No duplicate functionality with existing agents/skills (see differentiation table)
- [ ] Invoke 2-3 agents against a sample file to verify trimmed prompts produce complete output

## Implementation Phases

### Phase 1: Create 4 Agents

1. `plugins/soleur/agents/review/code-quality-analyst.md` (merged smell+refactoring)
2. `plugins/soleur/agents/review/test-design-reviewer.md`
3. `plugins/soleur/agents/review/legacy-code-expert.md`
4. `plugins/soleur/agents/review/ddd-architect.md`

### Phase 2: Create 2 Skills + Update Brainstorming

1. `plugins/soleur/skills/atdd-developer/SKILL.md`
2. `plugins/soleur/skills/user-story-writer/SKILL.md`
3. Update `plugins/soleur/skills/brainstorming/SKILL.md` with problem analysis routing

### Phase 3: Version Bump & Docs

1. Update `.claude-plugin/plugin.json` version to 1.9.0
2. Update `CHANGELOG.md` with [1.9.0] entry
3. Update `README.md` agent/skill counts and tables

### Phase 4: Validate

1. Run `bun test`
2. Verify no naming conflicts with existing agents
3. Invoke code-quality-analyst and test-design-reviewer against a sample file to verify output
4. Spot-check YAML frontmatter format matches existing agents

## Dependencies

- Source repo cloned at `/home/jean/git-repositories/jikig-ai/claude-code-agents`
- Worktree at `.worktrees/feat-add-engineering-skills`

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-09-add-engineering-skills-brainstorm.md`
- Spec: `knowledge-base/specs/feat-add-engineering-skills/spec.md`
- Source repo: https://github.com/andlaf-ak/claude-code-agents
- Issue: #27
- Review feedback: DHH, Kieran, Simplicity reviewers (2026-02-09)
