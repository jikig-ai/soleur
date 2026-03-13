---
title: "refactor: merge knowledge-base/features/ into knowledge-base/project/"
type: refactor
date: 2026-03-13
---

# refactor: merge knowledge-base/features/ into knowledge-base/project/

## Overview

Merge `knowledge-base/features/{brainstorms,learnings,plans,specs}` into `knowledge-base/project/` and delete stale `knowledge-base/specs/`. This simplifies the top-level taxonomy from "6 domain dirs + features + project" to "6 domain dirs + project".

## Problem Statement / Motivation

The knowledge-base taxonomy principle is "top-level directories = domains." `features/` breaks this — it's an artifact category, not a domain. `project/` is the natural home for all project-level artifacts including feature lifecycle content.

## Proposed Solution

Three-phase migration following the pattern established in commit 91ae5be:
1. `git mv` directories (preserving history)
2. Bulk update all path references
3. Grep-verify zero remaining old-path references

## Implementation Phases

### Phase 1: Directory Moves

```bash
cd .worktrees/feat-kb-flatten-features

# Ensure all files are tracked
git add knowledge-base/features/

# Move directories
git mv knowledge-base/features/brainstorms knowledge-base/project/brainstorms
git mv knowledge-base/features/learnings knowledge-base/project/learnings
git mv knowledge-base/features/plans knowledge-base/project/plans
git mv knowledge-base/features/specs knowledge-base/project/specs

# Delete stale top-level specs
git rm -r knowledge-base/specs/

# Remove empty features directory (git handles this automatically after mv)
```

### Phase 2: Update Path References (28 files, ~178 references)

Global find-and-replace `knowledge-base/features/` → `knowledge-base/project/` in all `.md` and `.sh` files under `plugins/`, `scripts/`, `.github/`, and `knowledge-base/` (excluding `archive/` and files inside the moved directories).

Do NOT update: files inside the moved directories (historical prose), `todos/` (stale), `AGENTS.md` (already correct).

#### Manual review: Directory tree diagrams (4 files)

These files contain bare `features/` references in directory tree diagrams and prose that won't be caught by the global find-and-replace. Review and rewrite manually:

| File | Special Handling |
|------|-----------------|
| `knowledge-base/project/components/knowledge-base.md` | Directory tree diagram (line 31: bare `features/`), examples, conventions |
| `knowledge-base/project/README.md` | Directory tree diagram (line 132: bare `features/`), convention path |
| `knowledge-base/project/constitution.md` | Convention path |
| `knowledge-base/project/components/agents.md` | learnings-researcher description |

### Phase 3: Verification

```bash
# Primary grep — must return zero matches
grep -r 'knowledge-base/features/' \
  plugins/ scripts/ .github/ AGENTS.md CLAUDE.md \
  knowledge-base/project/ knowledge-base/product/ \
  knowledge-base/engineering/ knowledge-base/marketing/ \
  knowledge-base/sales/ knowledge-base/support/ \
  knowledge-base/operations/ \
  --exclude-dir=archive \
  --include='*.md' --include='*.sh'

# Secondary grep — catch bare 'features/' in project docs tree diagrams
grep -n 'features/' \
  knowledge-base/project/README.md \
  knowledge-base/project/components/knowledge-base.md

# Verify directory structure
ls knowledge-base/project/
# Expected: brainstorms/ components/ constitution.md learnings/ plans/ README.md specs/

# Verify features/ and stale specs/ are gone
ls knowledge-base/features/ 2>&1  # Expected: No such file or directory
ls knowledge-base/specs/ 2>&1     # Expected: No such file or directory
```

## Acceptance Criteria

- [ ] `knowledge-base/features/` no longer exists
- [ ] `knowledge-base/specs/` (stale) no longer exists
- [ ] `knowledge-base/project/` contains: brainstorms/, components/, constitution.md, learnings/, plans/, README.md, specs/
- [ ] Zero grep hits for `knowledge-base/features/` in plugins/, scripts/, .github/, knowledge-base/ (excluding archive)
- [ ] Zero bare `features/` hits in project doc tree diagrams
- [ ] worktree-manager.sh creates spec dirs at `knowledge-base/project/specs/feat-<name>/`
- [ ] archive-kb.sh archives to `knowledge-base/project/{brainstorms,plans,specs}/archive/`
- [ ] compound-capture writes learnings to `knowledge-base/project/learnings/`
- [ ] Directory tree diagrams in README.md and knowledge-base.md reflect new structure

## Dependencies & Risks

- **Risk: Missing references** — Mitigated by Phase 3 grep verification (two-pass: full paths + bare tree diagrams)
- **Dependency: No other PRs touching `knowledge-base/features/` should merge first** — Check open PRs before merging

## References & Research

- Prior restructure: commit 91ae5be (156 references, 27 files)
- Follow-up fix: PR #572 (8 stale references in product docs)
- Brainstorm: `knowledge-base/features/brainstorms/2026-03-13-kb-flatten-features-brainstorm.md`
- Spec: `knowledge-base/features/specs/feat-kb-flatten-features/spec.md`
- Issue: #582
