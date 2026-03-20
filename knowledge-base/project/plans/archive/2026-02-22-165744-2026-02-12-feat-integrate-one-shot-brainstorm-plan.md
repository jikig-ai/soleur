---
title: "feat: Integrate One Shot into Brainstorm"
type: feat
date: 2026-02-12
issue: "#64"
version-bump: PATCH
---

# Integrate One Shot Command into Brainstorm

## Enhancement Summary

**Deepened on:** 2026-02-12
**Agents used:** code-simplicity-reviewer, architecture-strategist
**Key changes from review:** Merged separate Phase 0.5 into existing Phase 0 triage, replaced scored heuristic checklist with qualitative assessment, eliminated duplicate "plan only" option

## Overview

Modify the existing Phase 0 "requirement clarity" check in `brainstorm.md` to become a three-outcome triage: one-shot (simple + clear), plan (clear but complex), or brainstorm (unclear). This surfaces `/soleur:one-shot` during the existing assessment without adding a new phase.

## Problem Statement

Currently, `/soleur:brainstorm` offers only two paths when requirements are clear: proceed to planning or continue exploring. For simple, well-defined features (single-file changes, bug fixes, small improvements), the full brainstorm -> plan -> work pipeline adds unnecessary ceremony. The one-shot command exists but is not surfaced during brainstorm's requirement clarity check, forcing users to know about it independently.

## Proposed Solution

Expand the existing Phase 0 "If requirements are already clear" block to also assess simplicity. Instead of a separate Phase 0.5 with a scored checklist, use a single qualitative triage with three outcomes.

### Research Insights

**From code-simplicity-reviewer:**
- A separate "Phase 0.5" is unnecessary -- this is a refinement of the existing clarity check, not a new stage
- A scored heuristic checklist (6 items, 2+ threshold) adds false precision that an LLM will not apply consistently. A qualitative question works better and is more robust
- "Plan only" already exists in the current Phase 0 behavior. Adding it again duplicates existing functionality

**From architecture-strategist:**
- Phase 0 / Phase 0.5 ordering conflict: if Phase 0 fires first with a plan suggestion, Phase 0.5 never runs. Merging into a single triage eliminates this bypass
- Drop "under 30 minutes" heuristic -- unverifiable at assessment time before any codebase research
- Keep the brainstorming skill independent -- do not add one-shot references to SKILL.md. The skill should remain command-agnostic process knowledge
- Accept downstream friction (one-shot -> plan -> refinement) for now. Plan's own skip logic will fire quickly on simple features

**From learnings:**
- `parallel-plan-review-catches-overengineering.md`: Plans consistently shrink 70-90% after review. This plan's original Phase 0.5 with scored heuristics was itself over-engineered for an 8-line change
- `command-vs-skill-selection-criteria.md`: Routing to a different command is definitively an orchestration concern -- belongs in the command, not the skill

## Acceptance Criteria

- [x] Phase 0 of brainstorm.md performs a three-outcome triage (one-shot / plan / brainstorm)
- [x] Simple features get offered one-shot during the existing clarity check
- [x] Existing brainstorm flow is unchanged for complex or unclear features

## Test Scenarios

- Given a simple feature like "fix typo in README", when brainstorm runs Phase 0, then it proposes one-shotting
- Given a complex feature like "add authentication system", when brainstorm runs Phase 0, then it proceeds to brainstorm normally
- Given clear but complex requirements, when brainstorm runs Phase 0, then it suggests plan (existing behavior preserved)

## MVP

### plugins/soleur/commands/soleur/brainstorm.md

Replace the existing "If requirements are already clear" block (lines 47-48) with a three-outcome triage:

```markdown
**If requirements are already clear, also assess simplicity:**

Determine whether this is a simple feature -- one that a single developer could complete in one session without significant design decisions (e.g., bug fixes, single-file changes, small improvements following existing patterns).

**If clear AND simple:**
Use **AskUserQuestion tool** to suggest: "This looks straightforward enough for autonomous execution. What would you like to do?"

Options:
1. **One-shot it** - Run `/soleur:one-shot` for full autonomous pipeline (plan -> implement -> review -> PR)
2. **Plan first** - Run `/soleur:plan` to create a plan before implementing
3. **Brainstorm anyway** - Continue exploring the idea

**If one-shot is selected:** Pass the original feature description (including any issue references) to `/soleur:one-shot` and stop brainstorm execution.

**If clear but complex:**
Use **AskUserQuestion tool** to suggest: "Your requirements seem detailed enough to proceed directly to planning. Should I run `/soleur:plan` instead, or would you like to explore the idea further?"
```

**Files modified:** 1 (`plugins/soleur/commands/soleur/brainstorm.md`)
**Lines changed:** ~15 (replace existing 2-line block with expanded triage)

## Non-Goals

- Modifying the brainstorming skill (SKILL.md) -- keep it command-agnostic
- Adding flag-passing between one-shot and plan to skip refinement -- address when friction is reported
- Creating a separate Phase 0.5 -- unnecessary for this scope

## References

- Related issue: #64
- One-shot command: `plugins/soleur/commands/soleur/one-shot.md`
- Brainstorm command: `plugins/soleur/commands/soleur/brainstorm.md`
- Brainstorming skill: `plugins/soleur/skills/brainstorming/SKILL.md`
- Learning: `knowledge-base/learnings/2026-02-06-parallel-plan-review-catches-overengineering.md`
- Learning: `knowledge-base/learnings/2026-02-12-command-vs-skill-selection-criteria.md`
