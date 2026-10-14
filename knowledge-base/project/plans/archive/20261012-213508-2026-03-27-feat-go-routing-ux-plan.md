---
title: "feat: improve /go routing UX — brainstorm-first default"
type: feat
date: 2026-03-27
---

# Improve /go Routing UX — Brainstorm-First Default

Simplify `/soleur:go` from 4 intents to 3 by making brainstorm the default route for all non-bug, non-review work. Remove the confirmation step.

**Single file change:** `plugins/soleur/commands/go.md`

## Acceptance Criteria

- [x] `/go add dark mode` routes directly to `soleur:brainstorm` (no confirmation)
- [x] `/go fix the login bug` routes directly to `soleur:one-shot`
- [x] `/go review PR #100` routes directly to `soleur:review`
- [x] No AskUserQuestion confirmation step for classified intents
- [x] AskUserQuestion fallback only fires when intent is truly ambiguous
- [x] Worktree context detection (Step 1) unchanged
- [x] Original user input passed through as `args` to delegated skill

## Test Scenarios

- Given user says "add a loading spinner", when `/go` classifies, then routes to `soleur:brainstorm` (default)
- Given user says "fix the broken checkout", when `/go` classifies, then routes to `soleur:one-shot` (fix intent)
- Given user says "review PR #42", when `/go` classifies, then routes to `soleur:review`
- Given user says something ambiguous like "look at the settings page", when `/go` cannot classify, then presents AskUserQuestion with 3 options

## Context

### Key Learnings Applied

- **LLM semantic assessment over keyword matching** (learning: domain-leader-pattern-and-llm-detection). The command runs inside an LLM — leverage understanding, not regex.
- **Confirmation gates add friction without catching errors** (learning: passive-domain-routing-always-on-pattern). Domain routing already proved this. Same rationale applies to `/go`.
- **Keep it a thin router** (learning: simplify-workflow-thin-router-over-migration). The file should stay under 60 lines.
- **Linearize instructions** (learning: linearize-multi-step-llm-prompts). Put each instruction at the step where it executes.
- **Table-driven config** (learning: domain-prerequisites-refactor-table-driven-routing). The 3-intent table is the right structure.

### Existing Safety Net

Brainstorm Phase 0 already has an escape hatch: if requirements are clearly scoped, it offers "One-shot it" to skip brainstorm. This means routing features to brainstorm by default does NOT force unnecessary process — clear-scope work can still fast-track to one-shot, but with the benefit of Phase 0's assessment happening first.

## MVP

### plugins/soleur/commands/go.md

Replace everything from `## Step 2` to end of file. Step 1 (worktree context) is unchanged.

New Step 2 — Classify and Route:

Analyze the user input and classify intent using semantic assessment (not keyword matching):

| Intent | Trigger Signals | Routes To |
|--------|----------------|-----------|
| fix | Bug-related language — the user describes broken behavior, errors, regressions, or something that needs fixing | `soleur:one-shot` |
| review | "review PR", "check this code", PR number reference | `soleur:review` |
| default | Everything else — features, exploration, questions, generation, vague scope | `soleur:brainstorm` |

If intent is clear, invoke the skill directly via the **Skill tool** with the original user input as `args`. No confirmation step.

If intent is truly ambiguous, use **AskUserQuestion** with 3 options: Brainstorm (Recommended), Fix (one-shot), Review.

Note: The "generate" intent from the current file is collapsed into "default" with no behavioral change — both route to brainstorm.

## Domain Review

**Domains relevant:** Product

### Product (CPO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** Sound product direction. Brainstorm-as-default prevents misclassification. Edge cases handled by brainstorm Phase 0 escape hatch. CPO recommended a fifth "fix" intent (Option B); final design simplifies further to 3 intents with brainstorm as default.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-27-go-routing-ux-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-go-routing-ux/spec.md`
- Issue: #1188
- Current file: `plugins/soleur/commands/go.md` (60 lines)
