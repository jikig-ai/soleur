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

### Institutional Learnings Applied

From prior restructures (#566, #568, #570):

- **Grep scope must include ALL of `knowledge-base/`** — product docs contain cross-references agents follow as navigation (learning: `workflow-issues/2026-03-13-kb-restructure-grep-scope-must-include-product-docs.md`)
- **Check directory tree diagrams and prose** — they don't match path-pattern greps (learning: `2026-03-13-readme-self-references-missed-in-rename.md`)
- **Refresh project docs after restructures** — README counts, component docs, directory trees go stale (learning: `technical-debt/2026-02-12-overview-docs-stale-after-restructure.md`)
- **`git add` before `git mv`** for any uncommitted files (learning: `2026-02-24-git-add-before-git-mv-for-untracked-files.md`)
- **Do NOT update files inside moved directories** — historical prose, not executable (precedent: 91ae5be plan)

## Implementation Phases

### Phase 1: Directory Moves

Use `git mv` to move each subdirectory. Order matters: move specs last since our own spec is inside it.

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

Global find-and-replace: `knowledge-base/features/` → `knowledge-base/project/`

#### 2a. Shell Scripts (2 files)

| File | Refs | Key Paths |
|------|------|-----------|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | 7 | spec_dir, archive_dir, brainstorms/plans glob |
| `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` | 4 | brainstorms/plans/specs glob patterns |

#### 2b. Skills — SKILL.md Files (12 files)

| File | Refs |
|------|------|
| `plugins/soleur/skills/compound-capture/SKILL.md` | 25 |
| `plugins/soleur/skills/plan/SKILL.md` | 24 |
| `plugins/soleur/skills/compound/SKILL.md` | 16 |
| `plugins/soleur/skills/brainstorm/SKILL.md` | 10 |
| `plugins/soleur/skills/ship/SKILL.md` | 8 |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | 4 |
| `plugins/soleur/skills/archive-kb/SKILL.md` | 3 |
| `plugins/soleur/skills/spec-templates/SKILL.md` | 3 |
| `plugins/soleur/skills/merge-pr/SKILL.md` | 3 |
| `plugins/soleur/skills/work/SKILL.md` | 2 |
| `plugins/soleur/skills/one-shot/SKILL.md` | 1 |
| `plugins/soleur/skills/brainstorm-techniques/SKILL.md` | 1 |

#### 2c. Skill References/Assets (4 files)

| File | Refs |
|------|------|
| `plugins/soleur/skills/compound-capture/references/yaml-schema.md` | 13 |
| `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` | 2 |
| `plugins/soleur/skills/compound-capture/assets/critical-pattern-template.md` | 2 |
| `plugins/soleur/skills/compound-capture/assets/resolution-template.md` | 1 |

#### 2d. Agents (2 files)

| File | Refs |
|------|------|
| `plugins/soleur/agents/engineering/research/learnings-researcher.md` | 29 |
| `plugins/soleur/agents/product/cpo.md` | 1 |
| `plugins/soleur/agents/engineering/infra/infra-security.md` | 1 |

#### 2e. Commands (1 file)

| File | Refs |
|------|------|
| `plugins/soleur/commands/sync.md` | 6 |

#### 2f. Scripts (1 file)

| File | Refs |
|------|------|
| `scripts/generate-article-30-register.sh` | 1 |

#### 2g. Project Documentation — Self-References (4 files)

These require manual review beyond simple path replacement (directory trees, prose):

| File | Refs | Special Handling |
|------|------|-----------------|
| `knowledge-base/project/components/knowledge-base.md` | 7 | Directory tree diagram, examples, conventions |
| `knowledge-base/project/README.md` | 1 | Directory tree diagram, convention path |
| `knowledge-base/project/constitution.md` | 1 | Convention path |
| `knowledge-base/project/components/agents.md` | 1 | learnings-researcher description |

#### 2h. Domain Documentation (1 file)

| File | Refs | Note |
|------|------|------|
| `knowledge-base/product/business-validation.md` | 1 | Brainstorm reference in competitor table |

#### Files NOT to Update

- **Files inside `knowledge-base/features/`** (now `knowledge-base/project/`) — historical prose, not executable
- **`todos/` files** — completed status, pre-features/ paths already stale
- **`AGENTS.md`** — references `knowledge-base/project/constitution.md` (correct, no change needed)

### Phase 3: Verification

```bash
# Comprehensive grep — must return zero matches
grep -r 'knowledge-base/features/' \
  plugins/ scripts/ .github/ AGENTS.md CLAUDE.md \
  knowledge-base/project/ knowledge-base/product/ \
  knowledge-base/engineering/ knowledge-base/marketing/ \
  knowledge-base/sales/ knowledge-base/support/ \
  knowledge-base/operations/ \
  --exclude-dir=archive \
  --include='*.md' --include='*.sh'

# Verify directory structure
ls knowledge-base/project/
# Expected: brainstorms/ components/ constitution.md learnings/ plans/ README.md specs/

# Verify features/ is gone
ls knowledge-base/features/ 2>&1
# Expected: No such file or directory

# Verify stale specs/ is gone
ls knowledge-base/specs/ 2>&1
# Expected: No such file or directory
```

## Acceptance Criteria

- [ ] `knowledge-base/features/` no longer exists
- [ ] `knowledge-base/specs/` (stale) no longer exists
- [ ] `knowledge-base/project/` contains: brainstorms/, components/, constitution.md, learnings/, plans/, README.md, specs/
- [ ] Zero grep hits for `knowledge-base/features/` in plugins/, scripts/, .github/, knowledge-base/ (excluding archive)
- [ ] worktree-manager.sh creates spec dirs at `knowledge-base/project/specs/feat-<name>/`
- [ ] archive-kb.sh archives to `knowledge-base/project/{brainstorms,plans,specs}/archive/`
- [ ] compound-capture writes learnings to `knowledge-base/project/learnings/`
- [ ] Directory tree diagrams in README.md and knowledge-base.md reflect new structure

## Test Scenarios

- Given a new worktree is created with `worktree-manager.sh feature foo`, when the spec dir is created, then it should be at `knowledge-base/project/specs/feat-foo/`
- Given an archived brainstorm, when `archive-kb.sh` runs, then it should look in `knowledge-base/project/brainstorms/`
- Given a compound-capture learning, when saved, then it should write to `knowledge-base/project/learnings/<category>/`

## Dependencies & Risks

- **Risk: Missing references** — Mitigated by Phase 3 grep verification and learnings from prior restructures
- **Risk: Active worktrees on old paths** — Worktrees are isolated copies; they'll work until rebased from main. No blocking risk.
- **Dependency: No other PRs touching `knowledge-base/features/` should merge first** — Check open PRs before merging

## References & Research

- Prior restructure: commit 91ae5be (156 references, 27 files)
- Follow-up fix: PR #572 (8 stale references in product docs)
- Brainstorm: `knowledge-base/features/brainstorms/2026-03-13-kb-flatten-features-brainstorm.md`
- Spec: `knowledge-base/features/specs/feat-kb-flatten-features/spec.md`
- Issue: #582
