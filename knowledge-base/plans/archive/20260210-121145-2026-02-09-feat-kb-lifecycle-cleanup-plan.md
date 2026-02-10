---
title: "feat: Knowledge-Base Lifecycle Cleanup in /compound"
type: feat
date: 2026-02-09
updated: 2026-02-09
---

# feat: Knowledge-Base Lifecycle Cleanup in /compound

[Updated 2026-02-09] Simplified after two rounds of plan review: single extraction agent, branch-glob discovery, decoupled archival. Manual constitution promotion kept (serves different use case).

## Overview

Enhance `/soleur:compound` with a consolidation step that extracts key concepts from completed brainstorms, plans, and specs into the knowledge-base overview, then archives the source documents. This closes the lifecycle gap where completed feature artifacts accumulate without cleanup.

## Problem Statement

After features ship, brainstorms (11), plans (8), and specs (8) accumulate indefinitely. Key insights are trapped in individual documents instead of being consolidated into the overview (constitution.md, component docs, README.md). The knowledge-base overview should be the single source of truth, with completed artifacts archived.

## Non-Goals

- Automatic detection of stale documents (manual trigger via /compound menu is sufficient)
- Retroactive batch cleanup of all existing accumulated docs
- Changes to /ship or SessionStart hooks
- New standalone commands or skills
- Structured output schemas between agents (proposals are markdown text)

## Rollback Plan

All changes are `git mv` operations and markdown file edits in a single commit. If anything goes wrong: `git revert <commit>` restores all files to their original locations and undoes overview edits.

## Proposed Solution

Two logical steps added to `/compound` after learning capture, triggered by a new decision menu option:

1. **Discover & Extract** -- Glob for related artifacts by branch name, then a single agent reads them and proposes updates to relevant overview files (constitution, components, README)
2. **Archive** -- Move source documents to `*/archive/` directories with `git mv` (independent of whether extraction proposals were accepted)

The existing manual constitution promotion flow is **kept** -- it serves a different use case (ad-hoc promotion from any branch/learning, without feature artifacts).

## Technical Approach

### Integration Point

Add a new option to the compound-docs SKILL.md decision menu (after Step 7: Cross-Reference). Insert it at position **2** (right after "Continue workflow"), since consolidation is the natural next step after learning capture. Renumber remaining options. "Other" stays last.

```
2. Consolidate & archive KB artifacts - Extract insights to overview, archive source docs
```

Show this option only when on a `feat-*` branch. If selected and no artifacts found, notify: "No related artifacts found for this branch." and return to menu.

### Step 1: Discover & Extract

**Discovery (branch-glob only):**

Extract `<slug>` from current branch name (`feat-<slug>`). Glob for non-archived artifacts:

```bash
knowledge-base/brainstorms/*<slug>*
knowledge-base/plans/*<slug>*
knowledge-base/specs/feat-<slug>/
```

Exclude anything in `*/archive/` directories. Present discovered list to user for confirmation before proceeding. After showing glob results, offer the user a chance to add additional files manually (handles naming mismatches where filenames have extra words beyond the branch slug).

**Extraction (single agent):**

A single agent reads all discovered artifacts and proposes updates to whichever overview files are relevant:

| Target | What to extract | Example |
|--------|----------------|---------|
| `constitution.md` | Always/Never/Prefer rules by domain | "Architecture > Prefer: Lifecycle workflows should consolidate artifacts before archiving" |
| `overview/components/*.md` | New components added by the feature (skills, agents, commands) | Add entry to skills.md for a new skill |
| `overview/README.md` | Architectural insights, capability changes | New section or paragraph about a capability |

The agent may propose updates to one, two, or all three targets -- or none if the artifacts contain nothing worth codifying. Proposals are presented as markdown text (no structured JSON schema).

**Approval flow:**

Proposals presented one at a time per the constitution:

```
[1/N] Constitution Update
Proposed addition to Architecture > Prefer:
  "Lifecycle workflows should consolidate artifacts into overview before archiving"

Source: brainstorm (2026-02-09-kb-lifecycle-cleanup-brainstorm.md)

[A]ccept  [S]kip  [E]dit
```

- **Accept**: Apply the update immediately
- **Skip**: Move on, do not apply
- **Edit**: User provides corrected text, then re-shown for Accept/Skip

No summary confirmation pass -- accepted changes are applied as reviewed. Changes are version-controlled; `git revert` handles mistakes.

**Idempotency:** Before appending to constitution.md or component docs, check that a substantially similar rule/entry does not already exist.

### Step 2: Archive

After extraction (regardless of whether any proposals were accepted -- archival is independent):

1. Create archive directories if missing: `mkdir -p brainstorms/archive/ plans/archive/`
2. For each discovered artifact:
   - Generate timestamp: `YYYYMMDD-HHMMSS`
   - `git mv <source> <type>/archive/<timestamp>-<original-name>`
   - For spec directories: `git mv specs/feat-<slug>/ specs/archive/<timestamp>-feat-<slug>/`
3. If `git mv` fails (untracked file): `git add <file>` first, then retry
4. Present list of archived files

Ask user to confirm archival before executing. Use context-aware confirmation:
- If proposals were accepted: "Archive these N artifacts? [Y/n]"
- If all proposals were skipped: "No proposals were accepted. Archive these N artifacts anyway? [Y/n]"

**Commit strategy:** All changes (overview edits from extraction + archival moves) go in a **single commit**: `chore(kb): consolidate and archive feat-<slug> artifacts`. This preserves the clean `git revert` rollback.

### Relationship to Existing Features

- **Manual constitution promotion** (existing): **Kept** -- serves a different use case (ad-hoc promotion from any branch, any learning, without feature artifacts). The new extraction step handles feature-lifecycle consolidation; manual promotion handles one-off learning-to-constitution uplift.
- **Promote to Required Reading** (existing option 2): Orthogonal -- a learning can be promoted to required reading AND have its artifacts consolidated/archived
- **Worktree cleanup** (existing in /ship): Orthogonal -- worktree cleanup handles the git worktree; this handles the knowledge-base documents within it

## Acceptance Criteria

- [ ] New decision menu option at position 2 "Consolidate & archive KB artifacts" (visible on `feat-*` branches)
- [ ] Artifact discovery via branch-name glob finds related brainstorms, plans, specs
- [ ] User can add additional files manually after glob results
- [ ] Single extraction agent proposes updates to constitution, component docs, and/or overview
- [ ] User approval flow presents proposals one-at-a-time with Accept/Skip/Edit
- [ ] Approved updates applied to overview files with idempotency check
- [ ] Source documents archived to `*/archive/` with timestamp prefix using `git mv` (independent of extraction approvals)
- [ ] Context-aware archival confirmation (different message when all proposals skipped)
- [ ] All changes (overview edits + archival) in a single commit
- [ ] Graceful handling when no artifacts found
- [ ] Existing manual constitution promotion unchanged
- [ ] Existing /compound learning capture flow unchanged
- [ ] Version bump (MINOR) for plugin.json, CHANGELOG.md, README.md

## Dependencies & Risks

**Dependencies:**
- Current /compound skill structure (`compound-docs/SKILL.md`)
- Knowledge-base directory conventions (`feat-<name>` mapping)

**Risks:**
- Single-agent extraction quality may vary -- mitigated by user approval gate; can upgrade to multi-agent later if needed
- Discovery matching could miss artifacts with non-standard names -- mitigated by user confirmation of discovered list + manual file selection option

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `plugins/soleur/skills/compound-docs/SKILL.md` | Modify | Add consolidation step (discovery, extraction, approval, archive) at menu position 2; renumber existing options |
| `plugins/soleur/commands/soleur/compound.md` | Modify | Add menu option reference; update flow description |
| `plugins/soleur/.claude-plugin/plugin.json` | Modify | MINOR version bump |
| `plugins/soleur/CHANGELOG.md` | Modify | Document new feature and refactored promotion |
| `plugins/soleur/README.md` | Modify | Verify component counts |

## References

- **Brainstorm:** `knowledge-base/brainstorms/2026-02-09-kb-lifecycle-cleanup-brainstorm.md`
- **Spec:** `knowledge-base/specs/feat-kb-lifecycle-cleanup/spec.md`
- **GitHub Issue:** #30
- **Constitution principle:** "Lifecycle workflows with hooks must cover every state transition with cleanup trigger"
- **Constitution principle:** "For user approval flows, present items one at a time with Accept, Skip, and Edit options"
- **Constitution principle:** "Start with manual workflows; add automation only when users explicitly request it"
- **Plan review (round 1):** All 3 reviewers agreed on: single agent (not 3), branch-glob discovery, decoupled archival, no summary confirmation pass
- **Plan review (round 2):** Keep manual constitution promotion (different use case), remove non-feat fallback, menu position 2, single commit for all changes, context-aware archival confirmation
