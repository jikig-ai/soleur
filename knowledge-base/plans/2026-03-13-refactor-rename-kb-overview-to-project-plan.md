---
title: "refactor: rename knowledge-base/overview/ to knowledge-base/project/"
type: refactor
date: 2026-03-13
---

# refactor: rename knowledge-base/overview/ to knowledge-base/project/

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 4 (Scope, Technical Approach, Acceptance Criteria, Test Scenarios)
**Research sources:** Repo-wide grep audit, 3 relevant learnings, constitution analysis

### Key Improvements
1. Discovered sync.md has 12 `overview` mentions (not 7) -- includes `mkdir -p` brace expansion (line 41) and sync area name references (lines 4, 20, 116, 326, 441, 444)
2. Discovered compound-capture.md has 7 `overview` mentions (not 4) -- includes prose references on lines 383, 450, 455
3. Identified decision point: the sync command uses `overview` as a command argument/area name, not just a file path -- renaming the directory should also rename the sync area from `overview` to `project`

### New Considerations Discovered
- sync.md `mkdir -p` brace expansion on line 41 creates `overview/components` -- must change to `project/components`
- The `/sync overview` command name should change to `/sync project` for consistency
- Learnings from `2026-02-22-skill-count-propagation-locations.md`: always grep for the old value across the entire repo rather than relying on a memorized file list -- applied in Phase 4 verification

## Overview

Rename `knowledge-base/overview/` to `knowledge-base/project/` to reflect its actual contents after domain docs were moved out in #567. Only project-level files remain (constitution.md, README.md, components/) -- "project" is a more accurate label than "overview".

## Problem Statement / Motivation

After #567 moved domain-specific documents out of `knowledge-base/overview/`, the remaining files are all project-level configuration and documentation. The name "overview" no longer describes what the directory contains. Renaming to "project" improves navigability and semantic accuracy.

## Proposed Solution

Mechanical rename using `git mv` for history preservation, followed by find-and-replace across the files that reference the old path. Scoped to only the files that matter for runtime behavior (skills, commands, AGENTS.md, constitution self-references).

### Scope

**In scope (acceptance criteria):**

| Category | Files | Path refs | Prose/arg refs | Total |
|----------|-------|-----------|----------------|-------|
| `AGENTS.md` | 1 file | 1 | 0 | 1 |
| `plugins/soleur/skills/work/SKILL.md` | 1 file | 1 | 0 | 1 |
| `plugins/soleur/skills/compound/SKILL.md` | 1 file | 4 | 0 | 4 |
| `plugins/soleur/skills/compound-capture/SKILL.md` | 1 file | 4 | 3 | 7 |
| `plugins/soleur/skills/plan/SKILL.md` | 1 file | 1 | 0 | 1 |
| `plugins/soleur/skills/spec-templates/SKILL.md` | 1 file | 2 | 0 | 2 |
| `plugins/soleur/commands/sync.md` | 1 file | 8 | 6 | 14 |
| `knowledge-base/project/constitution.md` (self-refs) | 1 file | 0 | 2 | 2 |
| `knowledge-base/project/components/knowledge-base.md` (self-refs) | 1 file | 2 | 0 | 2 |

**Total: 9 files, ~34 references to update**

### Research Insights -- Reference Audit

The deepening phase discovered references the initial plan missed:

**sync.md (14 total, not 7):**
- Line 4: `argument-hint` includes `overview` as a valid area name
- Line 20: Valid areas list includes `overview`
- Line 41: `mkdir -p knowledge-base/{...,overview/components}` -- brace expansion creates the directory
- Line 116: Section header "Generate or update project overview documentation"
- Line 326: Conditional check for `overview` area name
- Line 441: Example text "Sync project overview"
- Line 444: Example command `/sync overview`
- Lines 131, 132, 160, 244, 391, 393, 395, 396: file path references (already in initial plan)

**compound-capture.md (7 total, not 4):**
- Line 383: "Which overview file to update" (prose)
- Line 450: "No overview updates applied" (prose)
- Line 455: "overview edits + archival moves" (prose)
- Lines 377, 378, 379, 394: file path references (already in initial plan)

**Out of scope (historical documents -- not updated):**

- `knowledge-base/brainstorms/` -- 30 references across archived brainstorm docs
- `knowledge-base/brainstorms/archive/` -- 25 references
- `knowledge-base/learnings/` -- 21 references across learning docs
- `knowledge-base/plans/` -- 197 references across plan docs
- `knowledge-base/marketing/` -- 14 references
- `knowledge-base/specs/` -- 72 references

These are historical records. Updating them would inflate the diff with no runtime benefit. They reference paths that existed at the time they were written.

## Non-goals

- Renaming any other knowledge-base directories
- Updating historical documents (brainstorms, learnings, plans, specs)
- Changing the structure within `knowledge-base/project/` (constitution.md, README.md, components/ stay as-is)
- Updating marketing docs in `knowledge-base/marketing/` that reference the old path

## Technical Approach

### Phase 1: Directory rename

Use `git mv` to rename the directory atomically. Per constitution rule: "Operations that modify the knowledge-base or move files must use `git mv` to preserve history." Also per constitution: "Skill instructions that use `git mv` must prepend `git add` on the source file to handle untracked files."

```bash
git add knowledge-base/overview/
git mv knowledge-base/overview/ knowledge-base/project/
```

### Phase 2: Update file path references in active files

Replace `knowledge-base/overview/` with `knowledge-base/project/` in these 7 files:

1. `AGENTS.md` -- line 3 (`knowledge-base/overview/constitution.md`)
2. `plugins/soleur/skills/work/SKILL.md` -- line 49
3. `plugins/soleur/skills/compound/SKILL.md` -- lines 172, 226, 259, 261
4. `plugins/soleur/skills/compound-capture/SKILL.md` -- lines 377, 378, 379, 394
5. `plugins/soleur/skills/plan/SKILL.md` -- line 45
6. `plugins/soleur/skills/spec-templates/SKILL.md` -- lines 99, 163
7. `plugins/soleur/commands/sync.md` -- lines 41, 131, 132, 160, 244, 391, 393, 395, 396

### Phase 2b: Update sync area name and prose references

The sync command uses `overview` as a semantic area name (a command argument). Rename the area from `overview` to `project` for consistency:

**sync.md changes:**
- Line 4: `argument-hint` -- replace `overview` with `project` in the area list
- Line 20: Valid areas list -- replace `overview` with `project`
- Line 116: Section header -- "Generate or update project overview documentation" (keep as-is -- "project overview" is descriptive text, not a path)
- Line 326: Area conditional -- replace `overview` with `project`
- Line 441: Example text -- "Sync project overview" -> "Sync project docs" or similar
- Line 444: Example command -- `/sync overview` -> `/sync project`

**compound-capture.md prose changes:**
- Line 383: "Which overview file to update" -> "Which project file to update"
- Line 450: "No overview updates applied" -> "No project updates applied"
- Line 455: "overview edits + archival moves" -> "project edits + archival moves"

### Phase 3: Update self-references within the moved directory

After the `git mv`, update references inside the renamed directory:

1. `knowledge-base/project/constitution.md` -- lines 146-147:
   - `overview/` documents what the project does -> `project/` documents what the project does
   - Component documentation in `overview/components/` -> `project/components/`
2. `knowledge-base/project/components/knowledge-base.md` -- lines 170, 184

### Phase 4: Verification

### Research Insights -- Verification Best Practice

From learning `2026-02-22-skill-count-propagation-locations.md`: "Always grep for the old value across the entire repo rather than relying on a memorized file list." Apply this principle by running verification against the full scoped paths, not just the files enumerated above.

```bash
# 1. Verify overview/ no longer exists
test ! -d knowledge-base/overview/ && echo "PASS: overview/ removed"

# 2. Verify zero path references in scoped paths
count=$(grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md 2>/dev/null | wc -l)
test "$count" -eq 0 && echo "PASS: zero path references in plugins/scripts/.github/AGENTS.md"

# 3. Verify zero area name references (catches /sync overview)
count=$(grep -rn "overview" plugins/soleur/commands/sync.md 2>/dev/null | grep -v 'project overview' | wc -l)
test "$count" -eq 0 && echo "PASS: sync area name updated"

# 4. Verify constitution self-references updated
grep -q 'project/' knowledge-base/project/constitution.md && echo "PASS: constitution self-refs"

# 5. Verify project/ directory has expected contents
test -f knowledge-base/project/constitution.md && test -f knowledge-base/project/README.md && test -d knowledge-base/project/components/ && echo "PASS: project/ contents intact"
```

### Edge Cases

- **Brace expansion in sync.md line 41:** The `mkdir -p knowledge-base/{...,overview/components}` uses shell brace expansion. Changing `overview` to `project` inside the braces is safe -- no quoting issues.
- **Prose vs path:** Some occurrences of "overview" in compound-capture.md are prose descriptions, not paths. These should still be updated for consistency, but changing "overview file" to "project file" is a semantic choice, not a mechanical replacement.
- **Constitution line 146:** The phrase "overview/ documents what the project does" uses the directory name as a concept. Changing to "project/ documents what the project does" is slightly awkward but consistent. The original constitution learning (project-overview-documentation-system.md) used this same "overview/ = what, constitution.md = how" pattern.

## Acceptance Criteria

- [x] `knowledge-base/overview/` directory no longer exists
- [x] `knowledge-base/project/` directory exists with identical contents (constitution.md, README.md, components/)
- [x] `grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md` returns zero matches
- [x] Constitution.md self-references updated (`overview/` -> `project/`)
- [x] `knowledge-base/project/components/knowledge-base.md` references updated
- [x] sync.md area name updated from `overview` to `project` (lines 4, 20, 326, 441, 444)
- [x] sync.md `mkdir -p` brace expansion updated (line 41)
- [x] compound-capture.md prose references updated (lines 383, 450, 455)
- [ ] All changes in a single atomic commit using `git mv`

## Test Scenarios

- Given the rename is complete, when running `grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md`, then zero matches are returned
- Given the rename is complete, when running `ls knowledge-base/project/`, then constitution.md, README.md, and components/ are present
- Given the rename is complete, when loading the plugin (reading AGENTS.md -> constitution.md path), then the path resolves correctly
- Given the rename is complete, when running compound skill, then constitution.md is found at the new path
- Given the rename is complete, when running `/sync project`, then the sync command recognizes `project` as a valid area
- Given the rename is complete, when running `/sync all`, then the `mkdir -p` creates `knowledge-base/project/components/` (not `overview/components/`)
- Given the rename is complete, when running compound-capture, then prose prompts reference "project" files, not "overview" files

## Context

- Split from #567 to reduce blast radius
- #567 (domain moves) ships first; this is a follow-up
- Semver: `semver:patch` -- no new functionality, internal path rename only

## Relevant Learnings Applied

1. **`2026-02-22-skill-count-propagation-locations.md`**: "Always grep for the old value across the entire repo rather than relying on a memorized file list." Applied in Phase 4 verification and used during deepening to discover missing references.
2. **`technical-debt/2026-02-12-overview-docs-stale-after-restructure.md`**: Confirms that overview docs become stale after restructures. This rename is part of that post-restructure cleanup.
3. **`implementation-patterns/project-overview-documentation-system.md`**: Documents the original design of `overview/` directory. The "overview/ = what, constitution.md = how" convention on constitution line 146 needs updating.

## References

- Parent issue: #567 (restructure knowledge-base by domain taxonomy)
- Closes #569
