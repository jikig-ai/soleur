# Go Routing UX Brainstorm

**Date:** 2026-03-27
**Status:** Decided
**Author:** Jean + Claude

## What We're Building

Simplify `/soleur:go` routing so that new features always go through brainstorm (where domain leaders assess implications in Phase 0.5) instead of being misclassified as "build" and sent directly to one-shot. Bug fixes continue to route to one-shot.

### Problem

The current `/go` router has a "build" intent that lumps feature requests and bug fixes together, routing both to `soleur:one-shot`. This causes:

1. **New features skip domain leader assessment** — brainstorm's Phase 0.5 (CPO, CMO, CTO, etc.) never fires because the feature never reaches brainstorm
2. **Misclassification is common** — signal words like "add", "implement", "build" trigger the "build" intent even for exploratory feature work
3. **Confirmation step doesn't help** — users see "I'll route this as build" but don't know what brainstorm would have provided (domain assessments, design decisions)
4. **Overkill for bug fixes** — one-shot's 10-step pipeline (plan approval, browser test, feature video) is heavyweight for simple fixes

### Current State (4 intents, confirmation step)

| Intent | Routes To |
|--------|-----------|
| explore | brainstorm |
| build (features + bugs) | one-shot |
| generate | brainstorm |
| review | review |

## Why This Approach

**Brainstorm as default** is the simplest rule that prevents misclassification:

- Every non-bug, non-review task goes through brainstorm
- Brainstorm's Phase 0 escape hatch already handles clear-scope work ("one-shot it" option)
- Domain leaders in Phase 0.5 catch product/marketing/legal blind spots early
- Even small enhancements may need domain input (e.g., a "small" copy change has marketing implications)

**Remove confirmation step** because:

- Better defaults make confirmation friction without value
- Users can always invoke `/soleur:brainstorm` or `/soleur:one-shot` directly if the router gets it wrong
- The router is a convenience, not a gate

## Key Decisions

1. **3 intents, not 4** — "explore", "generate", and "build (features)" merge into a single default path: brainstorm
2. **No confirmation step** — route directly based on classification
3. **Brainstorm is the default** — anything that isn't a bug fix or review goes to brainstorm
4. **Issue-aware bug detection** — when `#N` present, check issue labels (`type/bug`); if no labels, read the issue description to determine if it's a bug
5. **Keyword-based fallback** — without issue reference, detect bugs via signal words: "fix", "bug", "broken", "regression", "error"

### New Routing Table (3 intents, no confirmation)

| Intent | Trigger Signals | Routes To |
|--------|----------------|-----------|
| fix | "fix", "bug", "broken", "regression", "error"; `#N` with `type/bug` label or bug-like description | `soleur:one-shot` |
| review | "review PR", "check this code", PR number | `soleur:review` |
| default | everything else (features, exploration, questions, generation, vague scope) | `soleur:brainstorm` |

## Open Questions

None — design is decided.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Sound product direction. The classification boundary between features and bugs has edge cases ("update X to do Y", "improve performance") but the confirmation step handles misclassification, and brainstorm's Phase 0 escape hatch handles trivially clear features. Option B (add a fifth "fix" intent) was recommended as cleanest; the final design goes further by making brainstorm the default and reducing to 3 intents total.
