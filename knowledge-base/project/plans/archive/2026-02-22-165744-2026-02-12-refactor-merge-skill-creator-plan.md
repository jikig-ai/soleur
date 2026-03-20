---
title: Merge skill-creator and create-agent-skills into one skill
type: refactor
date: 2026-02-12
issue: "#63"
version_bump: PATCH
---

# Merge skill-creator and create-agent-skills into one skill

## Enhancement Summary

**Deepened on:** 2026-02-12
**Sections enhanced:** 3 (Merge Strategy, Acceptance Criteria, MVP)
**Agents used:** code-simplicity-reviewer, learnings-researcher (backtick-references, plugin-versioning)

### Key Improvements
1. Simplified merge strategy: link to reference files instead of inlining content into SKILL.md (avoids bloat and duplication)
2. Added cleanup for `core-principles.md` XML contradiction
3. Added backtick-to-markdown-link fix (from documented learning)

### Risks Discovered
- `references/core-principles.md` advocates XML tags, contradicting both skills' "no XML tags" guidance
- Several broken internal cross-references in moved reference files
- `skill-creator/SKILL.md` uses backtick references instead of markdown links (constitution violation)

## Overview

Two skills (`skill-creator` and `create-agent-skills`) overlap in purpose -- both handle skill authoring. Merge them into a single `skill-creator` skill that covers creation, refinement, and best practices.

## Problem Statement

Users face confusion about which skill to invoke for skill authoring tasks. The `create-agent-skills` name is less discoverable and its trigger keywords overlap with `skill-creator`.

## Proposed Solution

Move resource directories from `create-agent-skills` into `skill-creator`, link them from SKILL.md, and delete the redundant directory. Do NOT inline content from `create-agent-skills/SKILL.md` -- the reference files already cover it.

### What Each Skill Brings

**`skill-creator` (keep):**
- Concrete, process-oriented creation flow (Steps 1-6)
- `scripts/init_skill.py` -- initialization script
- `scripts/package_skill.py` -- packaging/validation script
- `scripts/quick_validate.py` -- quick validation
- Progressive disclosure design principle explanation
- Anatomy of a skill (directory structure, bundled resources)

**`create-agent-skills` (absorb then delete):**
- `references/` -- 12 reference files (official-spec, best-practices, common-patterns, etc.)
- `templates/` -- 2 templates (router-skill, simple-skill)
- `workflows/` -- 8 workflow files (audit, create, add-reference, etc.)
- SKILL.md content is already covered by the reference files being moved

### Merge Strategy

1. **Move resources** into `skill-creator/`: `references/`, `templates/`, `workflows/`
2. **Update SKILL.md description** to add trigger keywords: "audit skill", "skill best practices", "write a SKILL.md"
3. **Add reference links section** to SKILL.md pointing to moved files (use markdown links per constitution)
4. **Fix backtick references** in existing SKILL.md (replace backticks with markdown links per learning)
5. **Audit `references/core-principles.md`** -- strip or delete the XML advocacy section that contradicts "no XML tags" guidance
6. **Delete** `create-agent-skills/` directory
7. **Update counts** in plugin.json, README.md, CHANGELOG.md

**What NOT to do:** Do not inline content from `create-agent-skills/SKILL.md` into `skill-creator/SKILL.md`. The reference files (`best-practices.md`, `official-spec.md`, etc.) already cover frontmatter tables, naming conventions, auditing rubrics, patterns, and anti-patterns. Inlining would create bloat and violate progressive disclosure.

## Non-Goals

- Rewriting the merged skill from scratch
- Changing the `scripts/` behavior
- Adding new functionality beyond what both skills already provide
- Fixing broken cross-references within the moved reference files (separate issue)

## Acceptance Criteria

- [x] Single `skill-creator` skill handles both creation and refinement
- [x] `create-agent-skills/` directory removed
- [x] All resource directories from `create-agent-skills` preserved in `skill-creator/`
- [x] SKILL.md links to moved reference/template/workflow files using markdown links (not backticks)
- [x] `references/core-principles.md` does not advocate XML tags
- [ ] Existing backtick references in SKILL.md converted to markdown links (N/A -- backticks in SKILL.md are in example scenarios for hypothetical files, not actual file references)
- [x] README.md skill count updated (35 -> 34)
- [x] CHANGELOG.md documents the consolidation
- [x] plugin.json version bumped (PATCH) and description updated (35 -> 34)
- [x] Root README.md version badge updated
- [x] `skill-creator` description includes trigger keywords from both original skills

## Test Scenarios

- Given both skills exist, when merging, then all reference/template/workflow files from `create-agent-skills` are accessible under `skill-creator/`
- Given the merged skill, when a user says "create a skill", then `skill-creator` is triggered
- Given the merged skill, when a user says "audit skill" or "improve this skill", then `skill-creator` is triggered
- Given the merge is complete, when running `ls plugins/soleur/skills/create-agent-skills`, then the directory does not exist
- Given `skill-creator/SKILL.md`, when checking for backtick file references, then none are found (all use markdown links)

## MVP

### Phase 1: Move Resources

```bash
cp -r plugins/soleur/skills/create-agent-skills/references/ plugins/soleur/skills/skill-creator/
cp -r plugins/soleur/skills/create-agent-skills/templates/ plugins/soleur/skills/skill-creator/
cp -r plugins/soleur/skills/create-agent-skills/workflows/ plugins/soleur/skills/skill-creator/
```

### Phase 2: Update SKILL.md

Update `plugins/soleur/skills/skill-creator/SKILL.md`:
- Expand description to add: "audit skill", "skill best practices", "write a SKILL.md", "how to write skills"
- Add a "Reference Files" section linking to moved files with markdown links
- Add a "Workflows" section linking to moved workflow files
- Add a "Templates" section linking to moved template files
- Fix existing backtick references (e.g., `scripts/rotate_pdf.py` -> `[rotate_pdf.py](./scripts/rotate_pdf.py)`)

### Phase 3: Clean Up core-principles.md

Review `plugins/soleur/skills/skill-creator/references/core-principles.md`:
- Remove or rewrite any sections advocating XML tags in skill bodies
- Ensure consistency with "standard markdown headings" guidance

### Phase 4: Delete create-agent-skills

```bash
rm -rf plugins/soleur/skills/create-agent-skills/
```

### Phase 5: Version Bump (PATCH)

Update `plugins/soleur/.claude-plugin/plugin.json`:
- Bump version (PATCH)
- Update description count (35 -> 34 skills)

Update `plugins/soleur/CHANGELOG.md`:
- Add entry under "Changed" and "Removed" for consolidation

Update `plugins/soleur/README.md`:
- Update skill count (35 -> 34)
- Remove `create-agent-skills` from skill table
- Update `skill-creator` description in table

Update root `README.md`:
- Update version badge

Update `.github/ISSUE_TEMPLATE/bug_report.yml`:
- Update version placeholder if present

## References

- Issue: #63
- Learning: `knowledge-base/learnings/technical-debt/2026-02-12-skill-creator-overlap.md`
- Learning: `knowledge-base/learnings/technical-debt/2026-02-12-backtick-references-in-skills.md`
- Learning: `knowledge-base/learnings/plugin-versioning-requirements.md`
- Constitution: `knowledge-base/overview/constitution.md` (line 70: "When merging or consolidating duplicate functionality, prefer a single inline implementation")
