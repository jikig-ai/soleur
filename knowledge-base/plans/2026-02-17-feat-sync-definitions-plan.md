---
title: "feat: Sync definitions -- broad-scan learnings against skill/agent definitions"
type: feat
date: 2026-02-17
issue: "#110"
version_bump: PATCH
---

# feat: Sync definitions -- broad-scan learnings against skill/agent definitions

## Overview

Extend `/soleur:sync` with Phase 4 (Definition Sync) that scans all accumulated learnings against all skill/agent/command definitions and proposes one-line bullet edits. Also update compound-docs Step 8 to write `synced_to` for idempotency across both systems.

## Problem Statement

Compound routing (#104/#115, v2.12.0) handles session-scoped learning-to-definition routing. But cross-cutting learnings, retroactive learnings, and learnings from sessions where the relevant skill wasn't invoked are never routed. A periodic cold-path scan closes this gap.

## Proposed Solution

### Prerequisite: Update compound-docs Step 8

After compound routing writes a bullet to a definition, also update the learning file's `synced_to` frontmatter. This prevents Phase 4 from re-proposing bullets that compound already handled.

**File:** `plugins/soleur/skills/compound-docs/SKILL.md`

After Step 8.4 "Accept" branch, add:

```text
If accepted, also update the learning file's YAML frontmatter:
- If `synced_to` exists: append the definition name
- If `synced_to` absent: add `synced_to: [definition-name]`
- If no YAML frontmatter block: prepend a minimal `---` block with `synced_to`
```

### Phase 4: Definition Sync

Insert after existing Phase 3 (Write) in `sync.md`.

#### 4.1 Gate

If area is `all` (or no area specified), and both `knowledge-base/learnings/` and `plugins/soleur/` exist, proceed with Phase 4. Otherwise skip with an info message.

#### 4.2 Load

- List all learning files from `knowledge-base/learnings/` recursively, excluding `archive/` and `patterns/` directories. Extract each learning's title and any tags or metadata present (regardless of format -- YAML frontmatter, ad-hoc tags sections, or title only). Also extract `synced_to` from frontmatter if present.
- List all definitions by name: skills from `plugins/soleur/skills/*/SKILL.md`, agents from `plugins/soleur/agents/**/*.md`, commands from `plugins/soleur/commands/soleur/*.md`.

#### 4.3 Match

Present the full list of learning titles (with tags if available) and definition names. For each learning, determine which definitions it is relevant to. Skip pairs where the definition name is already in the learning's `synced_to` array.

For each relevant pair, read the full learning content and the full definition content. Draft a one-line bullet capturing the sharp-edge gotcha. Check the definition does not already contain a bullet covering this topic -- if it does, discard silently.

#### 4.4 Review

Present proposals one at a time using AskUserQuestion with Accept / Skip / Edit options.

For each proposal, display:

```text
## Definition Sync (1/N)

**Learning:** [learning-title]
**Definition:** [definition-name] ([type])
**Section:** [target-section-name]
**Proposed bullet:** "- [one-line bullet text]"

Accept / Skip / Edit / Done reviewing
```

**Accept:**
- Write the bullet to the definition file at the end of the target section
- Add definition name to learning's `synced_to` frontmatter
- If learning has no YAML frontmatter: prepend a minimal `---` block with `synced_to: [definition-name]`

**Skip:**
- Move to next proposal. No tracking written (proposal may reappear on next run).

**Edit:**
- User modifies bullet text. Re-display for final Accept/Skip.

**Done reviewing:**
- Stop Phase 4. Unreviewed proposals reappear on next `/sync` run.

#### 4.5 Summary

```text
## Definition Sync Complete

- Learnings scanned: N
- Proposals generated: P
- Accepted: A
- Skipped: S
- Not reviewed: U (will reappear next run)

### Definitions Updated
- [definition-name]: +N bullets
```

If zero proposals were generated: "Phase 4: All learnings already synced to relevant definitions (N learnings, M definitions scanned)."

## Acceptance Criteria

- [x] Running `/soleur:sync` (or `/sync all`) triggers Phase 4 after Phases 0-3
- [x] Running `/sync conventions` does NOT trigger Phase 4
- [x] Accepted proposals appear as bullets in target definition files
- [x] Accepted proposals update learning's `synced_to` frontmatter
- [x] Already-synced learnings (in `synced_to`) are not re-proposed
- [x] Learnings without YAML frontmatter are included in scanning
- [x] Phase 4 writes minimal YAML frontmatter to learnings that lack it (on accept only)
- [x] Compound-docs Step 8 writes `synced_to` to learning files after routing
- [x] Empty state shows informative message
- [x] Summary displays statistics

## Test Scenarios

### Happy Path
- Given a learning about worktree gotchas and a git-worktree skill definition, when `/sync` runs, then Phase 4 proposes a bullet for git-worktree/SKILL.md

### Synced Tracking
- Given a learning with `synced_to: [compound-docs]` in frontmatter, when `/sync` runs, then Phase 4 does not propose bullets for compound-docs from that learning

### No Frontmatter
- Given a learning with no YAML frontmatter, when `/sync` runs and user accepts a proposal, then Phase 4 prepends a `---` block with `synced_to: [definition-name]`

### Existing Bullet
- Given a definition that already contains a bullet covering the same topic, when Phase 4 evaluates the pair, then the proposal is discarded silently

### Scoped Area
- Given the user runs `/sync conventions`, when sync executes, then only Phases 0-3 run (Phase 4 skipped)

### Compound Routing Idempotency
- Given compound routing (Step 8) synced a learning to a definition and wrote `synced_to`, when `/sync` runs later, then Phase 4 does not re-propose that pair

### Empty State
- Given all learnings are already synced, when `/sync` runs, then Phase 4 displays "All learnings already synced"

## Dependencies & Risks

### Dependencies
- #104/#115 (compound routing) -- already shipped in v2.12.0

### Risks
- **Noisy proposals:** LLM may over-match learnings to definitions. Mitigation: user reviews every proposal; skip is free and fast.
- **Frontmatter mutation:** Adding YAML blocks to frontmatter-less files on accept. Mitigation: only adds `synced_to`, no backfilling.

## Non-Goals

- Fully automatic edits without user confirmation
- Replacing the constitution (project-wide rules stay centralized)
- Constitution cross-check (separate concern -- defer to its own plan if needed)
- `skipped_for` tracking (user can re-skip; definitions evolve)
- Metadata pre-filtering or scoring systems (LLM matches directly)
- New area arguments (`definitions` -- add when someone asks)
- Backfilling missing YAML fields on learnings
- Dry-run mode

## Rollback Plan

Revert the sync.md and compound-docs SKILL.md changes. Learning files that gained `synced_to` frontmatter retain it harmlessly (ignored by all existing tooling).

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-17-sync-definitions-brainstorm.md`
- Spec: `knowledge-base/specs/feat-sync-definitions/spec.md`
- Issue: #110
- Compound routing: #104, #115 (v2.12.0)
- Existing sync command: `plugins/soleur/commands/soleur/sync.md`
- Compound-docs skill: `plugins/soleur/skills/compound-docs/SKILL.md` (Step 8)
