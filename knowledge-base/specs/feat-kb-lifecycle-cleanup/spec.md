# Spec: Knowledge-Base Lifecycle Cleanup

**Feature:** feat-kb-lifecycle-cleanup
**Created:** 2026-02-09
**Updated:** 2026-02-09
**Status:** Ready for Implementation

## Problem Statement

After features ship, brainstorms, plans, and specs accumulate in the knowledge-base without cleanup. Key insights remain trapped in individual documents instead of being consolidated into the overview (constitution.md, component docs, README.md). The knowledge-base overview should be the single source of truth, with completed artifacts archived.

## Goals

1. Enhance `/soleur:compound` with a consolidation step that extracts key concepts into the knowledge-base overview
2. Archive source documents after consolidation to reduce repo bloat
3. Maintain user control via approval gates before any overview updates
4. Keep archival independent of extraction (archive even when no proposals accepted)

## Non-Goals

- Automatic detection of stale documents (manual trigger is sufficient)
- Retroactive batch cleanup of all existing docs (manual follow-up)
- Changes to /ship or SessionStart hooks
- New standalone commands or skills
- Structured output schemas between agents
- Removing or replacing the existing manual constitution promotion flow

## Related

- **GitHub Issue:** #30
- **Branch:** feat-kb-lifecycle-cleanup
- **Brainstorm:** `knowledge-base/brainstorms/2026-02-09-kb-lifecycle-cleanup-brainstorm.md`
- **Plan:** `knowledge-base/plans/2026-02-09-feat-kb-lifecycle-cleanup-plan.md`

## Functional Requirements

### FR1: Decision Menu Option
- Insert at position 2 in /compound decision menu (after "Continue workflow")
- Renumber existing options; "Other" stays last
- Show only on `feat-*` branches
- If no artifacts found, notify and return to menu

### FR2: Artifact Discovery
- Extract `<slug>` from current branch name (`feat-<slug>`)
- Glob for `knowledge-base/{brainstorms,plans}/*<slug>*` and `knowledge-base/specs/feat-<slug>/`
- Exclude `*/archive/` directories
- Present discovered list for user confirmation
- Offer manual file addition after glob results (handles naming mismatches)

### FR3: Knowledge Extraction
- Single agent reads all discovered artifacts
- Proposes updates to constitution.md (Always/Never/Prefer rules), component docs (new components), and/or overview README.md (architectural insights)
- Proposals presented as markdown text, one at a time (Accept/Skip/Edit)
- Idempotency: simple substring check, flag for user decision if similar exists

### FR4: Overview Updates
- Apply accepted proposals immediately (no summary confirmation)
- Constitution updates appended to correct domain/category
- Component doc updates add new entries
- Overview README updates add architectural notes

### FR5: Archival
- Archive all discovered artifacts regardless of extraction approvals
- Create archive directories on first use (`mkdir -p`)
- Use `git mv` with `YYYYMMDD-HHMMSS-<original-name>` naming
- Spec directories archived as `specs/archive/<timestamp>-feat-<slug>/`
- Context-aware archival confirmation (different message when all proposals skipped)
- All changes (overview edits + archival moves) in a single commit

## Technical Requirements

### TR1: Preserve Git History
- Use `git mv` for all archival moves
- If `git mv` fails on untracked file, `git add` first then retry

### TR2: Idempotent Updates
- Substring check before appending to overview files; flag and let user decide

### TR3: Rollback
- All changes in a single commit; `git revert` restores everything

## Success Criteria

- [ ] Decision menu option at position 2, visible on feat-* branches
- [ ] Branch-glob discovery finds related artifacts
- [ ] Manual file addition available after glob results
- [ ] Single extraction agent proposes updates to relevant overview files
- [ ] One-at-a-time approval flow with Accept/Skip/Edit
- [ ] Accepted updates applied with idempotency check
- [ ] Source documents archived with git history preserved
- [ ] Archival independent of extraction approvals
- [ ] Context-aware archival confirmation
- [ ] All changes in single commit
- [ ] Existing manual constitution promotion unchanged
- [ ] Existing /compound learning capture unchanged
