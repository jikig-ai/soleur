---
feature: improve-brainstorm
status: draft
date: 2026-02-12
---

# Improve Brainstorm Command

## Problem Statement

The `/soleur:brainstorm` command currently runs a single research agent (`repo-research-analyst`) and follows a structured, prescriptive question flow. This means brainstorming sessions start with limited context and follow a rigid script rather than adapting to the problem at hand. Other Soleur commands (review, plan, deepen-plan) leverage parallel sub-agents extensively, but brainstorm does not.

## Goals

- G1: Run 3 parallel research agents before user dialogue to gather rich context upfront
- G2: Adopt an OpenSpec-inspired conversational philosophy (curious, visual, adaptive)
- G3: Add spec-flow-analyzer after approach selection to catch gaps early
- G4: Maintain clean separation with plan phase (no framework-docs-researcher overlap)

## Non-Goals

- NG1: Adding DDD analysis to brainstorming (belongs in plan phase)
- NG2: Running framework-docs-researcher in brainstorm (plan already handles this)
- NG3: Changing the worktree/spec/issue creation workflow (Phase 3+)
- NG4: Modifying other commands (plan, review, etc.)

## Functional Requirements

- FR1: Phase 1 launches `repo-research-analyst`, `learnings-researcher`, and `best-practices-researcher` in parallel before any user dialogue
- FR2: Research results are synthesized into context that informs the brainstorm questions
- FR3: After user selects an approach (Phase 2), `spec-flow-analyzer` runs to validate completeness
- FR4: Brainstorming skill adopts curious/adaptive tone, ASCII diagram guidance, and thread-following behavior
- FR5: The "explore not prescribe" guardrail is explicit in the skill

## Technical Requirements

- TR1: All 3 research agents must be invoked using Task tool in a single message (parallel execution)
- TR2: Spec-flow-analyzer receives the chosen approach + research context as input
- TR3: Changes are limited to 2 files: `brainstorm.md` (command) and `SKILL.md` (skill)
- TR4: Version bump required per plugin AGENTS.md (MINOR bump -- new capability)
