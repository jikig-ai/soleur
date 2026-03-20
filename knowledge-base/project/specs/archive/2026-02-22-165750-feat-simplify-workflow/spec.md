# Spec: Simplify Workflow

**Issue:** #267
**Date:** 2026-02-22
**Status:** Draft

## Problem Statement

Soleur has 8 commands but usage data shows only 4 are regularly used (brainstorm, one-shot, sync, help). Brainstorm already routes to one-shot for simple tasks, effectively functioning as a unified entry point. The remaining commands (plan, work, review, compound) are pipeline stages that users rarely invoke directly. The command surface is larger than it needs to be.

## Goals

- G1: Reduce command surface from 8 to 3: `/soleur`, `/soleur:sync`, `/soleur:help`
- G2: Create a unified `/soleur` command that detects intent from natural language and routes to the right workflow
- G3: Preserve all existing capabilities -- nothing is removed, only reorganized
- G4: Existing command logic moves to skills with minimal rewriting

## Non-Goals

- Rewriting the internal logic of brainstorm, plan, work, review, compound, or one-shot
- Adding new capabilities or workflows
- Changing how sync or help work
- Plugin loader modifications (if bare `/soleur` isn't supported, fall back to `/soleur:go`)

## Functional Requirements

- FR1: `/soleur <natural language>` classifies intent into one of: explore, plan, build, review, capture, resume
- FR2: After classification, system proposes the route to the user for one-click confirmation
- FR3: User can redirect to a different intent at the confirmation step
- FR4: Domain leader routing (CTO, CMO, CPO, COO, CLO, CRO) fires for "explore" intent, skipped for others
- FR5: "resume" intent detects active worktree + unfinished tasks.md and offers to continue
- FR6: All existing command logic (brainstorm, plan, work, review, compound, one-shot) remains functional as skills

## Technical Requirements

- TR1: Unified command file is ~100 lines (thin router, not monolithic)
- TR2: 6 commands (brainstorm, plan, work, review, compound, one-shot) move from `commands/soleur/` to `skills/`
- TR3: Cross-references in AGENTS.md, CLAUDE.md, constitution, ship, and other files updated
- TR4: `/soleur:help` output reflects the new 3-command surface
- TR5: Plugin version bumped (MAJOR -- breaking change to command surface)

## Intent Classification

| Intent | Trigger Signals | Routes To |
|--------|----------------|-----------|
| explore | Questions, "brainstorm", "let's think about", vague scope | brainstorm skill |
| plan | "plan", explicit request for plan without implementation | plan skill |
| build | Bug fix, feature request, clear requirements, issue reference | one-shot skill |
| review | "review PR", "check this code", PR number reference | review skill |
| capture | "I learned", "document this", "remember that" | compound skill |
| resume | Active worktree detected, unfinished tasks.md | work skill (resume mode) |

## Open Questions

1. Does the plugin loader support a bare `/soleur` command? Needs investigation.
2. What does the "resume" detection heuristic look like concretely?
3. Should the version bump be MAJOR (breaking) or MINOR (additive) given that old commands become skills?
