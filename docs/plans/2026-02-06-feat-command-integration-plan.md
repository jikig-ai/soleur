---
title: "feat: Command Integration for Spec Workflow"
type: feat
date: 2026-02-06
priority: 2
dependencies:
  - 2026-02-06-feat-spec-workflow-foundation-plan.md
---

# Command Integration for Spec Workflow

## Overview

Update the four core commands (brainstorm, plan, work, compound) to use the knowledge-base. Human-in-the-loop for everything - no automation in v1.

## Problem Statement

Commands currently operate independently. We want them to:

- Read/write specs when `knowledge-base/` exists
- Fall back gracefully when it doesn't

## What We're NOT Building (v2)

- Tiered context disclosure (just load what's needed)
- Similarity scoring for patterns
- Automatic spec sync / divergence detection
- Automatic constitution promotion
- Automatic learning decay
- Pattern detection heuristics
- metrics.json analytics

## Proposed Solution

Add ~10 lines to each command. No new abstractions.

## Technical Approach

### brainstorm Changes

Add to end of `plugins/soleur/commands/soleur/brainstorm.md`:

```markdown
### Save Spec (if knowledge-base/ exists)

At the end of brainstorm:

1. Check if `knowledge-base/` directory exists
2. If yes:
   - Get feature name from user or derive from brainstorm topic
   - Run `worktree-manager.sh create-for-feature <name>`
   - Generate spec.md using template
   - Save to `knowledge-base/specs/feat-<name>/spec.md`
   - Announce: "Spec saved. Run soleur:plan to create tasks."
3. If no: Continue as current (save to docs/brainstorms/)
```

### plan Changes

Add to start of `plugins/soleur/commands/soleur/plan.md`:

```markdown
### Load Context (if knowledge-base/ exists)

At the start of plan:

1. Check if `knowledge-base/` directory exists
2. If yes:
   - Detect feature from current branch (`feat-<name>` pattern)
   - Read `knowledge-base/specs/feat-<name>/spec.md` if exists
   - Read `knowledge-base/constitution.md`
   - Use as input for planning
3. If no: Continue as current

### Save Tasks (at end)

1. If `knowledge-base/` exists and spec was loaded:
   - Generate tasks.md using template
   - Save to `knowledge-base/specs/feat-<name>/tasks.md`
   - Announce: "Tasks saved. Run soleur:work to implement."
2. If no: Continue as current (save to docs/plans/)
```

### work Changes

Add to start of `plugins/soleur/commands/soleur/work.md`:

```markdown
### Load Context (if knowledge-base/ exists)

At the start of work:

1. Check if `knowledge-base/` directory exists
2. If yes:
   - Detect feature from current branch
   - Read `knowledge-base/specs/feat-<name>/tasks.md` if exists
   - Read `knowledge-base/constitution.md`
   - Use tasks as work checklist (alongside TodoWrite)
3. If no: Continue as current
```

### compound Changes

Update `plugins/soleur/commands/soleur/compound.md`:

```markdown
### Save Learning (enhanced)

1. Capture session learning as current
2. If `knowledge-base/` exists:
   - Save to `knowledge-base/learnings/YYYY-MM-DD-topic.md`
3. If no:
   - Save to `docs/solutions/` as current

### Constitution Promotion (manual)

After saving learning:

1. Ask user: "Promote anything to constitution?"
2. If yes:
   - Show recent learnings (last 5)
   - User selects which to promote
   - Ask: "Which domain? (Code Style / Architecture / Testing)"
   - Ask: "Which category? (Always / Never / Prefer)"
   - User writes the principle (one line)
   - Append to `knowledge-base/constitution.md`
   - Commit: "constitution: add <domain> <category> principle"
3. If no: Done

### Worktree Cleanup (manual prompt)

At end:

1. Ask: "Feature complete? Clean up worktree?"
2. If yes: Run `git worktree remove .worktrees/feat-<name>`
3. If no: Done
```

## Backward Compatibility

All commands check `if [[ -d knowledge-base ]]` before any knowledge-base operations. Repos without it work exactly as before.

## Acceptance Criteria

- [ ] brainstorm creates worktree + spec.md when knowledge-base/ exists
- [ ] plan reads spec.md and constitution.md, creates tasks.md
- [ ] work reads tasks.md and constitution.md
- [ ] compound saves to learnings/, prompts for manual constitution promotion
- [ ] All commands fall back gracefully without knowledge-base/
- [ ] No new TypeScript interfaces or abstractions introduced

## Success Metrics

- Full workflow runs: brainstorm -> plan -> work -> compound
- Repos without knowledge-base/ still work identically
- Constitution grows via manual promotion (not algorithms)

## Files to Modify

| File | Change |
| ---- | ------ |
| `plugins/soleur/commands/soleur/brainstorm.md` | Add spec save at end |
| `plugins/soleur/commands/soleur/plan.md` | Add context load + tasks save |
| `plugins/soleur/commands/soleur/work.md` | Add context load |
| `plugins/soleur/commands/soleur/compound.md` | Add learning save + manual promotion prompt |

## Command Flow Summary

```text
brainstorm
  -> creates worktree + spec.md
  -> "Run soleur:plan"

plan
  -> reads spec.md, constitution.md
  -> creates tasks.md
  -> "Run soleur:work"

work
  -> reads tasks.md, constitution.md
  -> implements feature
  -> "Run soleur:compound"

compound
  -> saves learning
  -> asks: "Promote to constitution?" (manual)
  -> asks: "Clean up worktree?" (manual)
  -> "Done!"
```

## References

- Foundation plan: `docs/plans/2026-02-06-feat-spec-workflow-foundation-plan.md`
- Archived plans: `docs/plans/archive/`
