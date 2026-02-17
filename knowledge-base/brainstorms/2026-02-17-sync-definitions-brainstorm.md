# Brainstorm: Sync Definitions -- Broad-Scan Learnings Against Skill/Agent Definitions

**Date:** 2026-02-17
**Issue:** #110
**Status:** Decided
**Branch:** feat-sync-definitions

## What We're Building

Extend `/soleur:sync` with two new phases that retroactively scan all accumulated learnings against all skill/agent/command definitions and propose one-line bullet edits. This complements the compound routing (v2.12.0, #104/#115) which handles session-scoped detection. This handles the long tail: cross-cutting learnings, learnings from sessions where the relevant skill wasn't directly invoked, and historical knowledge that predates compound routing.

Additionally, a constitution cross-check phase scans constitution.md for rules that now duplicate content in specific definitions and proposes migrating them.

## Why This Approach

Compound routing (hot path) catches ~80% of learnings in-session. But some learnings are:
- **Cross-cutting** -- apply to multiple skills (e.g., a worktree gotcha affects git-worktree, ship, work, and plan skills)
- **Retroactive** -- captured before compound routing existed
- **Indirect** -- captured in sessions where the relevant skill wasn't the primary one invoked

A periodic cold-path scan closes this gap. Integrating it into `/soleur:sync` (rather than a new command) keeps the entry point simple -- one command for all knowledge-base synchronization.

## Key Decisions

### Entry Point: Auto-detect within /soleur:sync
- `/soleur:sync` runs both codebase analysis (existing Phases 0-3) AND definition sync (new Phase 4) AND constitution cross-check (new Phase 5) in one pass
- No new commands, no flags, no area arguments

### Sync Tracking: Frontmatter fields on learning files
- `synced_to: [skill-name, agent-name]` -- accepted proposals
- `skipped_for: [skill-name]` -- dismissed proposals (prevents re-proposals)
- Both fields are arrays of definition names
- Users can clear `skipped_for` entries to re-evaluate later
- Neither field is required -- absence means "not yet evaluated"

### Matching Strategy: Metadata pre-filter + LLM confirmation
- **Pass 1 (fast):** Match learning tags, module, component, and symptoms against definition names and content keywords. Generate candidate pairs.
- **Pass 2 (accurate):** LLM evaluates each candidate pair: "Is this learning relevant to this definition? If yes, draft a one-line bullet."
- This reduces the O(learnings x definitions) problem to a manageable set

### Review UX: Grouped by definition
- Group all proposals for the same definition together
- User reviews one definition at a time -- sees all proposed bullets before accepting/skipping
- Each bullet gets Accept/Skip/Edit
- Consistent with existing sync review pattern but batched for context

### Constitution Cross-Check: Included in v1
- Phase 5 runs after Phase 4 completes
- Scans constitution.md for rules that overlap with recently-synced definition bullets
- Proposes migration: remove from constitution, confirm it exists in the specific definition
- Same Accept/Skip/Edit UX

### Implementation: Extend sync.md directly
- Add Phase 4 (Definition Sync) and Phase 5 (Constitution Cross-Check) to existing sync command
- No new skills, agents, or commands
- Keeps architecture simple and consistent

## Open Questions

- **Threshold tuning:** How aggressive should metadata pre-filtering be? Start permissive (more LLM calls, fewer misses) or strict (faster, might miss connections)?
  - Decision: Start permissive, tighten if noise is a problem.
- **Batch size:** How many learnings to process per sync run? All unsynced, or cap at N?
  - Decision: Process all unsynced. If the corpus grows large, add a cap later.
- **Constitution migration granularity:** Migrate individual bullets or entire sections?
  - Decision: Individual bullets. Sections may contain rules that are genuinely project-wide.
