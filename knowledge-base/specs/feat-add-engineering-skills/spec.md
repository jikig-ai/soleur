# Spec: Add Engineering Skills

**Issue:** #27
**Branch:** feat-add-engineering-skills
**Date:** 2026-02-09

## Problem Statement

The soleur plugin has strong workflow/process skills (brainstorming, planning, shipping) but lacks methodology-driven engineering skills for code analysis, review, and structured development practices. The [claude-code-agents](https://github.com/andlaf-ak/claude-code-agents) repository contains 9 well-structured agents grounded in industry-standard books that fill these gaps.

## Goals

- G1: Add 6 analysis/review agents to `plugins/soleur/agents/`
- G2: Add 3 workflow skills to `plugins/soleur/skills/`
- G3: All agents/skills are language-agnostic
- G4: Agent prompts are lean (500-800 lines), leveraging Opus 4.6's built-in domain knowledge
- G5: Agents integrate with existing soleur workflows (composable via `Task()`)

## Non-Goals

- NG1: Rewriting the methodology content from scratch (adapt existing, trim to essentials)
- NG2: Changing existing soleur agents/skills
- NG3: Adding language-specific skills (Rails, Python, etc.)
- NG4: Building pipeline orchestration commands (future work)

## Functional Requirements

### Agents (FR1-FR6)

- FR1: `code-smell-detector` - Analyze code for quality issues, output structured report
- FR2: `refactoring-expert` - Recommend refactoring techniques based on detected smells
- FR3: `clean-coder` - Review code for Clean Code/SOLID/GRASP principle adherence
- FR4: `test-design-reviewer` - Score test quality using Farley's 8 properties
- FR5: `legacy-code-expert` - Analyze legacy code, identify seams, recommend safe modification paths
- FR6: `ddd-architect` - Review domain design for DDD pattern compliance

### Skills (FR7-FR9)

- FR7: `atdd-developer` - Guide user through RED/GREEN/REFACTOR implementation cycle
- FR8: `user-story-writer` - Decompose problems into INVEST-compliant user stories
- FR9: `problem-analyst` - Structured problem analysis before solutioning

## Technical Requirements

- TR1: Agents use soleur agent format (YAML frontmatter: name, description with examples, model)
- TR2: Skills use SKILL.md format (YAML frontmatter + markdown body + optional references/)
- TR3: Agents placed in appropriate category under `plugins/soleur/agents/`
- TR4: Plugin version bumped (MINOR - new agents/skills)
- TR5: Plugin README, CHANGELOG, plugin.json updated
- TR6: Tests pass (`bun test`)

## Success Criteria

- All 9 agents/skills created and properly formatted
- No duplicate functionality with existing soleur agents/skills
- Plugin version bumped and changelog updated
- `bun test` passes
