# Spec: Sync Definitions

**Issue:** #110
**Date:** 2026-02-17
**Branch:** feat-sync-definitions

## Problem Statement

Compound routing (#104/#115) handles session-scoped learning-to-definition routing. But cross-cutting learnings, retroactive learnings, and learnings from sessions where the relevant skill wasn't invoked are never routed. Additionally, constitution.md accumulates rules that overlap with specific definition files, creating redundancy.

## Goals

1. Extend `/soleur:sync` to scan all unsynced learnings against all definitions and propose one-line bullet edits
2. Track sync state via frontmatter on learning files to prevent duplicate proposals
3. Include constitution cross-check to propose migrating redundant rules to specific definitions
4. Maintain consistent UX with existing sync review pattern (Accept/Skip/Edit)

## Non-Goals

- Fully automatic edits without user confirmation
- Replacing the constitution (project-wide rules stay centralized)
- Restructuring definition file formats
- Building a separate matching engine or metadata system
- Modifying compound routing behavior

## Functional Requirements

- **FR1:** Phase 4 loads all learnings from `knowledge-base/learnings/` (recursive) and all definitions from `plugins/soleur/{skills,agents,commands}`
- **FR2:** Learnings with the target definition already in `synced_to` or `skipped_for` frontmatter are excluded from evaluation
- **FR3:** Metadata pre-filter matches learning tags/module/component against definition names and content keywords to generate candidate pairs
- **FR4:** LLM evaluates each candidate pair and drafts a one-line bullet if relevant
- **FR5:** Proposals are grouped by definition for review. User sees all proposed bullets for one definition before moving to the next
- **FR6:** Each bullet gets Accept/Skip/Edit. Accepted bullets are inserted into the definition file. Skipped bullets update `skipped_for` on the learning. Edited bullets are inserted as modified.
- **FR7:** After all definition syncs complete, Phase 5 scans constitution.md for rules that overlap with definition bullets and proposes migration (remove from constitution, confirm exists in definition)
- **FR8:** Frontmatter updates (`synced_to`, `skipped_for`) are written immediately after each review decision

## Technical Requirements

- **TR1:** No new commands, skills, or agents -- extend `plugins/soleur/commands/soleur/sync.md`
- **TR2:** Frontmatter fields `synced_to` and `skipped_for` are optional arrays of strings (definition names)
- **TR3:** Pre-filter must be fast enough to handle 100+ learnings x 50+ definitions without timeout
- **TR4:** Definition file discovery must respect plugin loader conventions: skills flat at `skills/<name>/SKILL.md`, agents recursive at `agents/**/*.md`, commands flat at `commands/soleur/*.md`
- **TR5:** Graceful degradation: skip Phase 4/5 if `knowledge-base/learnings/` or `plugins/soleur/` doesn't exist

## Acceptance Criteria

- [ ] Running `/soleur:sync` on a repo with unsynced learnings produces definition sync proposals
- [ ] Accepted proposals appear as bullets in the target definition file
- [ ] Skipped proposals are recorded in `skipped_for` and not re-proposed on next run
- [ ] Constitution cross-check identifies and proposes migration of redundant rules
- [ ] Already-synced learnings (in `synced_to`) are not re-proposed
