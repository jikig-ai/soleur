---
title: refactor: group specs/plans/brainstorms/learnings under features/
type: refactor
date: 2026-03-13
---

# Group specs/plans/brainstorms/learnings under features/

## Overview

Move the four feature-artifact directories (`specs/`, `plans/`, `brainstorms/`, `learnings/`) under a new `knowledge-base/features/` parent directory. This separates cross-cutting feature artifacts from domain-specific content, completing the second phase of the KB restructure (after #566 moved domain content, and #570 renamed `overview/` to `project/`).

## Problem Statement

After #566 and #570, domain content lives in canonical domain folders and project docs live under `project/`. But four directories that hold feature-scoped artifacts (`specs/`, `plans/`, `brainstorms/`, `learnings/`) still sit at the `knowledge-base/` root alongside domain folders. Grouping them under `features/` completes the taxonomy: `project/` for project docs, `features/` for feature artifacts, and `<domain>/` for domain content.

## Non-Goals

- Changing the internal structure of any of the four directories (archive/, subdirectories stay as-is)
- Updating content inside archived files (prose references in old plans/brainstorms are not executable)
- Splitting learnings by domain (learnings stay organized by feature/date under features/)
- Changing learnings category subdirectory names (e.g., `performance-issues/` stays)

## Proposed Solution

A single atomic `git mv` commit that moves the four directories, followed by a path reference update commit across all executable code.

### Move Manifest

| Source | Destination |
|--------|-------------|
| `knowledge-base/specs/` | `knowledge-base/features/specs/` |
| `knowledge-base/plans/` | `knowledge-base/features/plans/` |
| `knowledge-base/brainstorms/` | `knowledge-base/features/brainstorms/` |
| `knowledge-base/learnings/` | `knowledge-base/features/learnings/` |

### Convention Update

Old convention: `feat-<name>` maps to `knowledge-base/specs/feat-<name>/`
New convention: `feat-<name>` maps to `knowledge-base/features/specs/feat-<name>/`

## Technical Approach

### Phase 1: Directory Move

```bash
mkdir -p knowledge-base/features
git mv knowledge-base/specs knowledge-base/features/
git mv knowledge-base/plans knowledge-base/features/
git mv knowledge-base/brainstorms knowledge-base/features/
git mv knowledge-base/learnings knowledge-base/features/
```

### Phase 2: Update Path References in Executable Code

27 files across plugins/, scripts/, and knowledge-base/project/ need path updates. Content inside knowledge-base/features/ (archived plans, old brainstorms) does NOT need updating -- those are prose, not executable.

#### 2.1 Shell Scripts (highest risk -- silent runtime failure)

| File | Old Pattern | New Pattern | Context |
|------|-------------|-------------|---------|
| `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` | `knowledge-base/brainstorms/`, `knowledge-base/plans/`, `knowledge-base/specs/` | `knowledge-base/features/brainstorms/`, `knowledge-base/features/plans/`, `knowledge-base/features/specs/` | Discovery globs and archive paths (lines 98-110) |
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | `knowledge-base/specs/` (lines 152, 182, 194, 426-427, 464-466) | `knowledge-base/features/specs/` | `create_for_feature()` spec dir creation and `cleanup_merged_worktrees()` archival; also `knowledge-base/brainstorms/` and `knowledge-base/plans/` in `archive_kb_files` calls |
| `scripts/generate-article-30-register.sh` | `knowledge-base/specs/` | `knowledge-base/features/specs/` | Spec directory reference |

#### 2.2 Skill SKILL.md Files (agent-executed -- runtime failure)

| File | Patterns to Update |
|------|-------------------|
| `plugins/soleur/skills/plan/SKILL.md` | `knowledge-base/specs/`, `knowledge-base/plans/`, `knowledge-base/brainstorms/`, `knowledge-base/learnings/` |
| `plugins/soleur/skills/brainstorm/SKILL.md` | `knowledge-base/brainstorms/`, `knowledge-base/learnings/`, `knowledge-base/specs/` |
| `plugins/soleur/skills/brainstorm-techniques/SKILL.md` | `knowledge-base/brainstorms/` |
| `plugins/soleur/skills/compound/SKILL.md` | `knowledge-base/specs/`, `knowledge-base/learnings/` |
| `plugins/soleur/skills/compound-capture/SKILL.md` | `knowledge-base/specs/`, `knowledge-base/brainstorms/`, `knowledge-base/plans/`, `knowledge-base/learnings/` |
| `plugins/soleur/skills/compound-capture/assets/critical-pattern-template.md` | `knowledge-base/learnings/` |
| `plugins/soleur/skills/compound-capture/assets/resolution-template.md` | `knowledge-base/learnings/` |
| `plugins/soleur/skills/compound-capture/references/yaml-schema.md` | `knowledge-base/learnings/` |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | `knowledge-base/plans/`, `knowledge-base/learnings/` |
| `plugins/soleur/skills/work/SKILL.md` | `knowledge-base/specs/`, `knowledge-base/plans/` |
| `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` | `knowledge-base/specs/` |
| `plugins/soleur/skills/ship/SKILL.md` | `knowledge-base/specs/`, `knowledge-base/plans/`, `knowledge-base/brainstorms/` |
| `plugins/soleur/skills/merge-pr/SKILL.md` | `knowledge-base/specs/`, `knowledge-base/plans/` |
| `plugins/soleur/skills/one-shot/SKILL.md` | `knowledge-base/specs/` |
| `plugins/soleur/skills/spec-templates/SKILL.md` | `knowledge-base/specs/` |
| `plugins/soleur/skills/archive-kb/SKILL.md` | `knowledge-base/specs/`, `knowledge-base/brainstorms/`, `knowledge-base/plans/` |

#### 2.3 Agent Files

| File | Patterns to Update |
|------|-------------------|
| `plugins/soleur/agents/engineering/research/learnings-researcher.md` | `knowledge-base/learnings/` (13 category paths in routing table + search paths) |
| `plugins/soleur/agents/engineering/infra/infra-security.md` | `knowledge-base/learnings/` |
| `plugins/soleur/agents/product/cpo.md` | `knowledge-base/specs/` |

#### 2.4 Commands

| File | Patterns to Update |
|------|-------------------|
| `plugins/soleur/commands/sync.md` | `knowledge-base/learnings/` |

#### 2.5 Project Documentation

| File | Patterns to Update |
|------|-------------------|
| `knowledge-base/project/constitution.md` | `knowledge-base/specs/` (convention path on line 149) |
| `knowledge-base/project/components/knowledge-base.md` | `knowledge-base/specs/`, `knowledge-base/learnings/`, `knowledge-base/brainstorms/`, `knowledge-base/plans/` (directory tree, examples, related files) |
| `knowledge-base/project/components/agents.md` | `knowledge-base/learnings/` |
| `knowledge-base/project/README.md` | `knowledge-base/specs/`, `knowledge-base/plans/` |

### Phase 3: Verification

```bash
# Must all return zero matches in executable code
grep -r 'knowledge-base/specs/' plugins/ scripts/ .github/ AGENTS.md
grep -r 'knowledge-base/plans/' plugins/ scripts/ .github/ AGENTS.md
grep -r 'knowledge-base/brainstorms/' plugins/ scripts/ .github/ AGENTS.md
grep -r 'knowledge-base/learnings/' plugins/ scripts/ .github/ AGENTS.md

# Constitution convention path updated
grep 'knowledge-base/features/specs/feat-' knowledge-base/project/constitution.md

# Archiving script uses new paths
grep 'knowledge-base/features/' plugins/soleur/skills/archive-kb/scripts/archive-kb.sh
grep 'knowledge-base/features/' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
```

### Phase 4: Smoke Test

Run `archive-kb.sh --dry-run` from the worktree to verify the archiving script discovers artifacts under the new paths:

```bash
bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run
```

## Critical Dependencies and Risks

### Archiving System (Highest Risk)

The archiving system has broken silently before (92 artifacts missed -- see learning `2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`). Three components need synchronized updates:

1. **archive-kb.sh** -- Hardcoded globs `knowledge-base/{brainstorms,plans}/*slug*` and `knowledge-base/specs/feat-slug`
2. **worktree-manager.sh cleanup-merged** -- `archive_kb_files()` calls reference `knowledge-base/brainstorms` and `knowledge-base/plans`; spec archival references `knowledge-base/specs/$safe_branch`
3. **compound-capture SKILL.md** -- Prose instructions reference `knowledge-base/brainstorms/`, `knowledge-base/plans/`, `knowledge-base/specs/feat-<slug>/`

All three must update atomically. If archive-kb.sh is updated but worktree-manager.sh is missed, merged-branch cleanup silently stops archiving brainstorms and plans.

### learnings-researcher Agent

Contains a 13-row routing table mapping feature types to `knowledge-base/learnings/<category>/` paths. Every row needs `knowledge-base/features/learnings/<category>/` prefix. Missing even one row means that category's learnings become invisible to the research agent.

### Feature-Spec Convention

Multiple skills use the convention `feat-<name>` -> `knowledge-base/specs/feat-<name>/`. This convention appears in:
- constitution.md (line 149)
- knowledge-base.md component doc
- plan SKILL.md, work SKILL.md, compound SKILL.md, brainstorm SKILL.md, ship SKILL.md, spec-templates SKILL.md

All must update to `knowledge-base/features/specs/feat-<name>/`.

## Acceptance Criteria

- [ ] All 4 dirs moved under `knowledge-base/features/`
- [ ] `grep -r` for old root-level paths returns zero in executable code (plugins/, scripts/, .github/, AGENTS.md)
- [ ] `archive-kb.sh --dry-run` discovers artifacts under new paths
- [ ] `worktree-manager.sh` `create_for_feature()` creates spec dirs under `features/specs/`
- [ ] `worktree-manager.sh` `cleanup_merged_worktrees()` archives to `features/specs/archive/`, `features/brainstorms/archive/`, `features/plans/archive/`
- [ ] learnings-researcher routing table has all 13 categories updated
- [ ] constitution.md convention path updated to `knowledge-base/features/specs/feat-<name>/`

## Test Scenarios

- Given a feature branch `feat/new-thing`, when `archive-kb.sh` runs, then it discovers artifacts in `knowledge-base/features/brainstorms/`, `knowledge-base/features/plans/`, and `knowledge-base/features/specs/feat-new-thing/`
- Given `worktree-manager.sh feature new-thing` runs, when it creates the spec dir, then the path is `knowledge-base/features/specs/feat-new-thing/`
- Given `cleanup_merged_worktrees()` runs for a merged branch, when it archives specs/brainstorms/plans, then archived artifacts land in `knowledge-base/features/{specs,brainstorms,plans}/archive/`
- Given `learnings-researcher` is invoked for a performance issue, when it searches, then it looks in `knowledge-base/features/learnings/performance-issues/`
- Given `compound-capture` runs on `feat/something`, when it discovers artifacts for consolidation, then it finds them under `knowledge-base/features/`
- Given `soleur:plan` creates a plan, when it writes the file, then the output goes to `knowledge-base/features/plans/`

## Rollback Plan

`git revert HEAD~1..HEAD` on main cleanly undoes both commits (moves + reference updates). If only the move commit landed, `git revert HEAD` restores original paths.

## Semver Intent

`semver:patch` -- internal path restructure, no user-facing behavior change.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-12-kb-domain-structure-brainstorm.md`
- Parent issue: #567 (domain moves, shipped as #566)
- Sibling issue: #569 (overview/ rename, shipped as #570)
- This issue: #568
- Learning: `knowledge-base/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`
- Learning: `knowledge-base/learnings/2026-02-06-docs-consolidation-migration.md`
