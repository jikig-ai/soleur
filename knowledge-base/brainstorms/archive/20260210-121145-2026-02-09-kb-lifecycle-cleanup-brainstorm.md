# Brainstorm: Knowledge-Base Lifecycle Cleanup

**Date:** 2026-02-09
**Status:** Ready for Planning
**GitHub Issue:** #30

## What We're Building

An enhancement to `/soleur:compound` that, after capturing a learning, analyzes the related brainstorm, plan, and spec documents to:

1. **Extract key concepts** and merge them into the knowledge-base overview (constitution.md, component docs, README.md)
2. **Archive source docs** (brainstorms, plans, specs, and mature learnings) to their respective `/archive/` directories

This makes the knowledge-base overview the single source of truth while keeping the repo lean.

## Why This Approach

Currently, brainstorms, plans, and specs accumulate indefinitely after features ship. There are 11 brainstorms, 8 plans, and 8 active specs — many for completed features. Key insights are trapped in these documents instead of being consolidated into the overview. The `/compound` skill is the natural integration point because:

1. It already captures learnings — extending it to consolidate all knowledge artifacts is a natural fit
2. It runs in-context while the feature is fresh, producing better extraction
3. It's the "knowledge capture" step in the workflow, so adding "knowledge consolidation" here makes conceptual sense
4. Adding inline phases keeps the workflow simple (vs. a separate skill or hook)

## Key Decisions

### 1. Integration Point: /compound
- **Decision:** Enhance `/compound` with new phases after learning capture (not a separate skill, not a SessionStart hook)
- **Why:** In-context extraction is higher quality. One workflow is simpler than two. /compound is already the knowledge consolidation tool.

### 2. What Gets Extracted
- **Decision:** Full overview update — constitution rules (Always/Never/Prefer), component docs (agents.md, skills.md, etc.), and main overview/README.md
- **Why:** The overview should be the single source of truth. All artifact types contain valuable information that belongs in different parts of the overview.

### 3. Archival Strategy
- **Decision:** Move to archive dirs (brainstorms/archive/, plans/archive/, specs/archive/) with timestamp prefix
- **Why:** Keeps full history and is browsable. Deleting loses original context; summarize-then-archive adds complexity for marginal benefit.

### 4. Learnings Lifecycle
- **Decision:** Learnings are also candidates for archival once their insights are well-established in constitution/overview
- **Why:** Issue #30 explicitly calls this out. Once a learning's key insight is part of the constitution, the detailed learning doc becomes historical reference.

### 5. Archive Naming Convention
- **Decision:** `YYYYMMDD-HHMMSS-<original-name>` prefix in archive directories
- **Why:** Consistent with existing `specs/archive/` convention, provides chronological ordering, prevents name collisions.

## Proposed /compound Flow (Enhanced)

```
Existing flow:
  1. Capture context (parallel subagents)
  2. Create learning document
  3. Present decision menu

New phases after learning capture:
  4. Discover related artifacts
     - Find brainstorm, plan, spec matching the feature/topic
     - Find mature learnings whose insights are in constitution
  5. Extract key concepts (parallel subagents)
     - Subagent 1: Analyze artifacts for constitution rules (Always/Never/Prefer)
     - Subagent 2: Analyze for component doc updates (new skills, agents, commands)
     - Subagent 3: Analyze for overview/architectural insights
  6. Present extraction proposals to user
     - Show what would be added to constitution.md
     - Show what would be added to component docs
     - Show what would be added to overview
     - User approves/edits/rejects each
  7. Apply approved updates
     - Update constitution.md, component docs, overview
  8. Archive source documents
     - Move brainstorm, plan, spec to archive dirs
     - Present list of archived files
     - Commit archival
```

## Scope Boundaries

**In scope:**
- New phases in /compound for extraction and archival
- Archive directories for brainstorms and plans (specs already has one)
- Parallel subagent analysis for knowledge extraction
- User approval gate before any updates

**Out of scope:**
- Automatic detection of "stale" documents (manual trigger via /compound is sufficient)
- Retroactive cleanup of existing accumulated docs (can be done manually after feature ships)
- Changes to /ship or SessionStart hooks
- New standalone commands

## Open Questions

None — all decisions made through brainstorming dialogue.

## Next Steps

1. Run `/soleur:plan` to create implementation tasks
2. Implement new /compound phases
3. Create archive directories for brainstorms and plans
4. Test with existing accumulated documents
