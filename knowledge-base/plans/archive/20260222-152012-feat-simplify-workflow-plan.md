---
title: "feat: Simplify Workflow with Unified /soleur:go Entry Point"
type: feat
date: 2026-02-22
---

# Simplify Workflow with Unified /soleur:go Entry Point

## Overview

Add `/soleur:go` as a thin router that classifies user intent and delegates to existing commands. Update `/soleur:help` to show 3 recommended commands. Existing commands stay as-is.

## Divergences from Brainstorm

The brainstorm proposed moving 6 commands to skills and using bare `/soleur`. Planning revealed:
- Bare `/soleur` is not supported by the plugin loader (commands require `namespace:name` format)
- Command-to-skill migration has zero user-facing benefit (invocation syntax is identical) but 5 critical risks (naming collision, argument passthrough, one-shot pipeline breakage, 53+ cross-references, ship/compound reference breakage)

Decision: add-only approach. No migrations, no renames, no cross-reference updates.

## Phase 1: Create /soleur:go + Update /soleur:help

Create `plugins/soleur/commands/soleur/go.md` (~40 lines):

**Frontmatter:**

```yaml
name: soleur:go
description: Unified entry point that classifies intent and routes to the right workflow command
argument-hint: "[what you want to do]"
```

**Logic:**

1. If no arguments, ask "What would you like to do?" (free text, then classify)
2. If cwd is inside a worktree, mention it: "You're in worktree feat-X. Want to continue that or start something new?"
3. Classify intent into 3 categories. If ambiguous, ask the user to choose.
4. Propose the route via AskUserQuestion, user confirms or redirects
5. Delegate to the matching command via Skill tool with the full argument string

**Intent classification:**

| Intent | Trigger Signals | Delegates To |
|--------|----------------|--------------|
| explore | Questions, "brainstorm", "think about", vague scope | `/soleur:brainstorm` |
| build | Bug fix, feature request, issue ref (#N), clear requirements | `/soleur:one-shot` |
| review | "review PR", "check code", PR number reference | `/soleur:review` |

Domain leader routing stays in brainstorm -- the router has zero domain awareness.

**Implementation notes:**
- Use `#$ARGUMENTS` template syntax and angle-bracket placeholders per constitution rules (no shell variable expansion)
- If command exceeds 100 lines, extract intent classification into a reference file

**Update /soleur:help** to show:

```text
## Getting Started

/soleur:go <what you want to do>   -- The recommended way to use Soleur
/soleur:sync                        -- Sync knowledge base from codebase
/soleur:help                        -- Show this help

## Workflow Commands (Advanced)

/soleur:brainstorm  /soleur:plan  /soleur:work
/soleur:review      /soleur:compound  /soleur:one-shot
```

## Acceptance Criteria

- [ ] `/soleur:go fix the login bug` classifies as "build" and delegates to one-shot
- [ ] `/soleur:go` with no args asks "What would you like to do?"
- [ ] `/soleur:go review PR #42` classifies as "review" and delegates to review
- [ ] `/soleur:go let's explore auth options` classifies as "explore" and delegates to brainstorm
- [ ] Ambiguous input presents options instead of guessing
- [ ] `/soleur:help` shows 3 recommended commands prominently
- [ ] All existing commands continue to work unchanged

## Non-Goal

Do not modify existing commands or plugin loader.

## Version Bump

MINOR (new command, no breaking changes). Ship workflow handles plugin.json, CHANGELOG.md, README.md, root README badge, and count reconciliation.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-22-simplify-workflow-brainstorm.md`
- Spec: `knowledge-base/specs/feat-simplify-workflow/spec.md`
- Issue: #267
