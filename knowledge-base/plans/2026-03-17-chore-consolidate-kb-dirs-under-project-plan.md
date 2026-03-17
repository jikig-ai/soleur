---
title: "chore: consolidate knowledge-base artifact dirs under project/"
type: chore
date: 2026-03-17
semver: patch
---

# chore: consolidate knowledge-base artifact dirs under project/

## Overview

After the KB restructure sequence (PRs #566, #570, #573, #581, #602, #606), artifact directories ended up split across three locations. The canonical location is `knowledge-base/project/` — brainstorms/, learnings/, plans/, and specs/ should all live under project/. PR #606 incorrectly updated skill references to point to root-level paths instead.

### Current State

| Directory | File Count | Status |
|-----------|------------|--------|
| `knowledge-base/brainstorms/` | 5 + 2 archive | Root-level (should not exist) |
| `knowledge-base/project/brainstorms/` | 28 + 82 archive | Canonical |
| `knowledge-base/learnings/` | 18 flat files | Root-level (should not exist) |
| `knowledge-base/project/learnings/` | 180+ flat + 12 category subdirs | Canonical |
| `knowledge-base/plans/` | 17 + 2 archive | Root-level (should not exist) |
| `knowledge-base/project/plans/` | 84 + 116 archive | Canonical |
| `knowledge-base/specs/` | 18 dirs + 1 archive | Root-level (should not exist) |
| `knowledge-base/project/specs/` | 84 dirs + 117 archive + external/ | Canonical |
| `knowledge-base/features/specs/` | 2 dirs + 1 archive | Ghost from PR #573 |

### Target State

- `knowledge-base/brainstorms/` — removed (merged into project/)
- `knowledge-base/learnings/` — removed (merged into project/)
- `knowledge-base/plans/` — removed (merged into project/)
- `knowledge-base/specs/` — removed (merged into project/)
- `knowledge-base/features/` — removed (merged into project/)
- All skill, agent, and script references point to `knowledge-base/project/` paths

## Non-Goals

- Changing `knowledge-base/project/constitution.md`, `README.md`, or `components/` (these stay)
- Updating content inside archived/historical files
- Removing domain directories (`engineering/`, `marketing/`, etc.)

## Proposed Solution

Two-phase approach: (A) merge files via `git mv`, then (B) update all references.

### Phase A: File Moves (single atomic commit)

#### A1: Merge root brainstorms/ → project/brainstorms/

```text
knowledge-base/brainstorms/*.md → knowledge-base/project/brainstorms/
knowledge-base/brainstorms/archive/* → knowledge-base/project/brainstorms/archive/
```

No filename collisions (different date ranges).

#### A2: Merge root learnings/ → project/learnings/

```text
knowledge-base/learnings/*.md → knowledge-base/project/learnings/
```

Root learnings/ has no subdirectories. Project learnings/ has 12 category subdirs. No collisions.

#### A3: Merge root plans/ → project/plans/

```text
knowledge-base/plans/*.md → knowledge-base/project/plans/
knowledge-base/plans/archive/* → knowledge-base/project/plans/archive/
```

No filename collisions.

#### A4: Merge root specs/ → project/specs/

Two directories overlap (`feat-plausible-goals` and `feat-weekly-analytics-improvements`):
- Root has `session-state.md`, project/ has `tasks.md` — complementary files, merge via individual file moves.

```text
knowledge-base/specs/feat-*/ → knowledge-base/project/specs/ (non-overlapping: direct move)
knowledge-base/specs/feat-plausible-goals/session-state.md → knowledge-base/project/specs/feat-plausible-goals/
knowledge-base/specs/feat-weekly-analytics-improvements/session-state.md → knowledge-base/project/specs/feat-weekly-analytics-improvements/
knowledge-base/specs/archive/* → knowledge-base/project/specs/archive/
```

#### A5: Merge features/specs/ → project/specs/

```text
knowledge-base/features/specs/feat-linkedin-presence → knowledge-base/project/specs/
knowledge-base/features/specs/feat-ralph-loop-idle-detection → knowledge-base/project/specs/
knowledge-base/features/specs/archive/20260313-130805-feat-utm-conventions → knowledge-base/project/specs/archive/
```

### Phase B: Update References

All files outside `knowledge-base/` that reference root-level artifact paths must be updated to `knowledge-base/project/` paths.

#### B1: Shell Scripts (runtime-critical)

| File | Changes |
|------|---------|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Lines 196, 238, 494-495, 519, 521, 779: change `knowledge-base/specs/`, `knowledge-base/brainstorms/`, `knowledge-base/plans/` → `knowledge-base/project/specs/`, etc. Remove `knowledge-base/features/specs/` fallback (line 495). Remove `knowledge-base/project/` fallback entries that searched legacy paths (lines 496, 520, 522) — project/ IS the canonical path now. |
| `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` | Lines 99, 101, 112-113: change `knowledge-base/brainstorms`, `knowledge-base/plans`, `knowledge-base/specs` → `knowledge-base/project/brainstorms`, etc. Remove `knowledge-base/features/specs` fallback (line 113). Remove `knowledge-base/project/` fallback entries (lines 100, 102, 114) — they become the primary paths. |

#### B2: Skill Definitions (agent behavior)

Every SKILL.md that references root-level artifact paths. Full list:

| File | Patterns to Replace |
|------|-------------------|
| `plugins/soleur/skills/plan/SKILL.md` | `knowledge-base/brainstorms/` → `knowledge-base/project/brainstorms/`, `knowledge-base/specs/` → `knowledge-base/project/specs/`, `knowledge-base/plans/` → `knowledge-base/project/plans/`, `knowledge-base/learnings/` → `knowledge-base/project/learnings/` |
| `plugins/soleur/skills/brainstorm/SKILL.md` | Same four replacements |
| `plugins/soleur/skills/brainstorm-techniques/SKILL.md` | `knowledge-base/brainstorms/` → `knowledge-base/project/brainstorms/` |
| `plugins/soleur/skills/compound/SKILL.md` | `knowledge-base/learnings/`, `knowledge-base/specs/` |
| `plugins/soleur/skills/compound-capture/SKILL.md` | All four artifact paths |
| `plugins/soleur/skills/ship/SKILL.md` | All four artifact paths |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | `knowledge-base/plans/`, `knowledge-base/learnings/` |
| `plugins/soleur/skills/merge-pr/SKILL.md` | `knowledge-base/brainstorms/`, `knowledge-base/plans/`, `knowledge-base/specs/` |
| `plugins/soleur/skills/archive-kb/SKILL.md` | All artifact paths + remove features/ refs |
| `plugins/soleur/skills/one-shot/SKILL.md` | `knowledge-base/specs/` |
| `plugins/soleur/skills/spec-templates/SKILL.md` | `knowledge-base/specs/` |
| `plugins/soleur/skills/work/SKILL.md` | `knowledge-base/specs/` |

#### B3: Agent Definitions

| File | Patterns to Replace |
|------|-------------------|
| `plugins/soleur/agents/engineering/research/learnings-researcher.md` | `knowledge-base/learnings/` → `knowledge-base/project/learnings/` |
| Any other agents referencing artifact paths (verify with grep) |

#### B4: Other Files

| File | Changes |
|------|---------|
| `scripts/generate-article-30-register.sh` | Update `knowledge-base/project/specs/archive/` path (already correct if file stays in project/) |
| `knowledge-base/project/components/knowledge-base.md` | Update directory tree to show brainstorms/, learnings/, plans/, specs/ under project/ |
| `knowledge-base/project/README.md` | Update directory structure (lines 132-137) |
| `AGENTS.md` | Check for any artifact path references |
| `knowledge-base/project/constitution.md` | Check for any artifact path references |

### Phase C: Verification

1. `knowledge-base/brainstorms/` does not exist
2. `knowledge-base/learnings/` does not exist
3. `knowledge-base/plans/` does not exist
4. `knowledge-base/specs/` does not exist
5. `knowledge-base/features/` does not exist
6. `knowledge-base/project/brainstorms/` has all files (33+)
7. `knowledge-base/project/learnings/` has all files (198+) including 12 category subdirs
8. `knowledge-base/project/plans/` has all files (100+)
9. `knowledge-base/project/specs/` has all dirs (104+)
10. `feat-plausible-goals` has both `tasks.md` and `session-state.md`
11. `feat-weekly-analytics-improvements` has both `tasks.md` and `session-state.md`
12. `grep -rn 'knowledge-base/brainstorms\|knowledge-base/learnings\|knowledge-base/plans\|knowledge-base/specs' plugins/ scripts/ .github/ AGENTS.md` returns zero hits (all updated to project/ paths)
13. No references to `knowledge-base/features/` remain outside archive docs

## Acceptance Criteria

- [ ] Root-level `brainstorms/`, `learnings/`, `plans/`, `specs/` directories removed
- [ ] `knowledge-base/features/` directory removed
- [ ] All files consolidated under `knowledge-base/project/` equivalents
- [ ] All skill, agent, and script references updated to `knowledge-base/project/` paths
- [ ] `feat-plausible-goals` and `feat-weekly-analytics-improvements` have merged contents
- [ ] Documentation (README.md, components/knowledge-base.md) updated
- [ ] Single atomic commit for file moves, separate commit for reference updates (or combined if clean)
- [ ] `git log --follow` works on moved files

## Test Scenarios

- Given cleanup is complete, `ls knowledge-base/brainstorms/` fails (dir does not exist)
- Given cleanup is complete, `ls knowledge-base/project/brainstorms/` lists 33+ files
- Given cleanup is complete, `ls knowledge-base/project/learnings/bug-fixes/` lists category files
- Given cleanup is complete, `ls knowledge-base/project/specs/feat-plausible-goals/` shows both `tasks.md` and `session-state.md`
- Given cleanup is complete, `grep -rn 'knowledge-base/brainstorms/' plugins/` returns no matches
- Given cleanup is complete, `grep -rn 'knowledge-base/specs/' plugins/` returns no matches (all say project/specs/)
- Given cleanup is complete, archive-kb.sh discovers artifacts at `knowledge-base/project/` paths

## Rollback Plan

`git revert HEAD` cleanly undoes all `git mv` operations. Reference updates can be reverted independently.

## Learnings Applied

1. `git add` before `git mv` for untracked files (learning 2026-02-24)
2. Post-move grep sweep for stale cross-references (learning 2026-03-13)
3. README self-references missed in directory rename (learning 2026-03-13)
4. Grep scope must include product docs, not just code (learning 2026-03-13)

## Workflow Improvement: Planning Direction Confirmation

**Root cause of the original wrong plan:** The planner trusted PR #606's code changes as evidence of canonical direction without asking the user. PR #606 itself was incorrect — it moved references away from project/ instead of toward it.

**Proposed fix:** When a plan involves merging directory A into B (or vice versa), the plan skill should explicitly confirm the direction with the user before proceeding, even in pipeline mode. Directional ambiguity is a critical decision, not a detail to infer from code evidence.

## Semver Intent

`semver:patch` — internal file consolidation + reference fixes, no user-facing behavior change.
