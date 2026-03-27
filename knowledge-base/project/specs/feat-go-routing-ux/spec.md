# Spec: Go Routing UX

**Issue:** #1188
**Branch:** feat-go-routing-ux
**Brainstorm:** [2026-03-27-go-routing-ux-brainstorm.md](../../brainstorms/2026-03-27-go-routing-ux-brainstorm.md)

## Problem Statement

The `/soleur:go` command misclassifies new features as "build" intent, routing them directly to `soleur:one-shot` and skipping brainstorm's domain leader assessments (Phase 0.5). This bypasses CPO, CMO, CTO, and other domain leaders who catch blind spots early.

## Goals

- G1: New features always route through brainstorm for domain leader assessment
- G2: Bug fixes route to one-shot for direct implementation
- G3: Remove the confirmation step to reduce friction
- G4: Simplify intent classification from 4 intents to 3

## Non-Goals

- NG1: Changing brainstorm's Phase 0 escape hatch (it already handles clear-scope features)
- NG2: Routing bug fixes to `fix-issue` instead of `one-shot` (separate concern)
- NG3: Adding issue label checking to brainstorm or other skills
- NG4: Changing the worktree context detection (Step 1)

## Functional Requirements

- FR1: `/go` classifies intent into 3 categories: `fix`, `review`, `default`
- FR2: `fix` intent routes to `soleur:one-shot` — triggered by signal words ("fix", "bug", "broken", "regression", "error")
- FR3: `review` intent routes to `soleur:review` — triggered by "review PR", "check this code", PR number references
- FR4: `default` intent routes to `soleur:brainstorm` — everything else (features, exploration, questions, generation)
- FR5: When input contains `#N` reference, check issue labels via `gh issue view <N> --json labels`; if `type/bug` label present, classify as `fix`
- FR6: When input contains `#N` reference with no labels, read issue description to determine if bug-like
- FR7: If intent cannot be determined (truly ambiguous), use AskUserQuestion with all 3 options
- FR8: No confirmation step for classified intents — route directly

## Technical Requirements

- TR1: Single file change: `plugins/soleur/commands/go.md`
- TR2: Worktree context detection (Step 1) unchanged
- TR3: Preserve pass-through of original user input as `args` parameter to delegated skills
