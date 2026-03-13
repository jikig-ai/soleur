---
title: "refactor: rename knowledge-base/overview/ to knowledge-base/project/"
type: refactor
date: 2026-03-13
---

# refactor: rename knowledge-base/overview/ to knowledge-base/project/

## Overview

Rename `knowledge-base/overview/` to `knowledge-base/project/` to reflect its actual contents after domain docs were moved out in #567. Only project-level files remain (constitution.md, README.md, components/) -- "project" is a more accurate label than "overview".

## Problem Statement / Motivation

After #567 moved domain-specific documents out of `knowledge-base/overview/`, the remaining files are all project-level configuration and documentation. The name "overview" no longer describes what the directory contains. Renaming to "project" improves navigability and semantic accuracy.

## Proposed Solution

Mechanical rename using `git mv` for history preservation, followed by find-and-replace across the files that reference the old path. Scoped to only the files that matter for runtime behavior (skills, commands, AGENTS.md, constitution self-references).

### Scope

**In scope (acceptance criteria):**

| Category | Files | Reference count |
|----------|-------|----------------|
| `AGENTS.md` | 1 file | 1 reference |
| `plugins/soleur/skills/work/SKILL.md` | 1 file | 1 reference |
| `plugins/soleur/skills/compound/SKILL.md` | 1 file | 4 references |
| `plugins/soleur/skills/compound-capture/SKILL.md` | 1 file | 4 references |
| `plugins/soleur/skills/plan/SKILL.md` | 1 file | 1 reference |
| `plugins/soleur/skills/spec-templates/SKILL.md` | 1 file | 2 references |
| `plugins/soleur/commands/sync.md` | 1 file | 7 references |
| `knowledge-base/overview/constitution.md` (self-refs) | 1 file | 2 references (relative paths on lines 146-147) |
| `knowledge-base/overview/components/knowledge-base.md` (self-refs) | 1 file | 2 references |

**Total: 9 files, ~24 references to update**

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

Use `git mv` to rename the directory atomically:

```bash
git add knowledge-base/overview/
git mv knowledge-base/overview/ knowledge-base/project/
```

### Phase 2: Update references in active files

Update `knowledge-base/overview/` to `knowledge-base/project/` in these 7 files:

1. `AGENTS.md` -- line 3 (constitution.md path)
2. `plugins/soleur/skills/work/SKILL.md` -- line 49
3. `plugins/soleur/skills/compound/SKILL.md` -- lines 172, 226, 259, 261
4. `plugins/soleur/skills/compound-capture/SKILL.md` -- lines 377, 378, 379, 394
5. `plugins/soleur/skills/plan/SKILL.md` -- line 45
6. `plugins/soleur/skills/spec-templates/SKILL.md` -- lines 99, 163
7. `plugins/soleur/commands/sync.md` -- lines 131, 132, 160, 244, 391, 393, 395, 396

### Phase 3: Update self-references within the moved directory

After the `git mv`, update references inside the renamed directory:

1. `knowledge-base/project/constitution.md` -- lines 146-147 (relative `overview/` paths become `project/`)
2. `knowledge-base/project/components/knowledge-base.md` -- lines 170, 184

### Phase 4: Verification

Run the acceptance criteria checks:

```bash
# Verify overview/ no longer exists
test ! -d knowledge-base/overview/ && echo "PASS: overview/ removed"

# Verify zero references in scoped paths
count=$(grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md 2>/dev/null | wc -l)
test "$count" -eq 0 && echo "PASS: zero references in plugins/scripts/.github/AGENTS.md"

# Verify constitution self-references updated
grep -c 'project/' knowledge-base/project/constitution.md
```

## Acceptance Criteria

- [ ] `knowledge-base/overview/` directory no longer exists
- [ ] `knowledge-base/project/` directory exists with identical contents (constitution.md, README.md, components/)
- [ ] `grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md` returns zero matches
- [ ] Constitution.md self-references updated (`overview/` -> `project/`)
- [ ] `knowledge-base/project/components/knowledge-base.md` references updated
- [ ] All changes in a single atomic commit using `git mv`

## Test Scenarios

- Given the rename is complete, when running `grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md`, then zero matches are returned
- Given the rename is complete, when running `ls knowledge-base/project/`, then constitution.md, README.md, and components/ are present
- Given the rename is complete, when loading the plugin (reading AGENTS.md -> constitution.md path), then the path resolves correctly
- Given the rename is complete, when running compound skill, then constitution.md is found at the new path

## Context

- Split from #567 to reduce blast radius
- #567 (domain moves) ships first; this is a follow-up
- Semver: `semver:patch` -- no new functionality, internal path rename only

## References

- Parent issue: #567 (restructure knowledge-base by domain taxonomy)
- Closes #569
