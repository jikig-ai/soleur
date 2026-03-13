---
title: "chore: clean up stale knowledge-base/project/ references in SKILL.md files"
type: chore
date: 2026-03-13
issue: "#604"
semver: patch
---

# chore: clean up stale knowledge-base/project/ references in SKILL.md files

## Overview

After the KB restructure (#566, #569), four artifact directories moved from `knowledge-base/project/` to top-level `knowledge-base/`:

| Legacy Path | Current Canonical Path |
|---|---|
| `knowledge-base/project/learnings/` | `knowledge-base/learnings/` |
| `knowledge-base/project/brainstorms/` | `knowledge-base/brainstorms/` |
| `knowledge-base/project/plans/` | `knowledge-base/plans/` |
| `knowledge-base/project/specs/` | `knowledge-base/specs/` |

Three paths under `knowledge-base/project/` remain correct and must NOT be changed:

- `knowledge-base/project/constitution.md` (stays)
- `knowledge-base/project/components/` (stays)
- `knowledge-base/project/README.md` (stays)

PR #602 fixed the two shell scripts (`archive-kb.sh`, `worktree-manager.sh`) that silently failed. This issue tracks the broader documentation cleanup: 154 stale references across 20 plugin `.md` files plus 1 in `AGENTS.md`.

## Scope

### Files to Update (20 plugin files + 1 repo root)

**High priority -- contain executable code snippets with stale paths:**

| File | Count | Notes |
|---|---|---|
| `plugins/soleur/skills/compound-capture/SKILL.md` | 25 | `find`, `grep -r`, `mkdir -p`, `cat >>` with legacy learnings paths |
| `plugins/soleur/skills/compound/SKILL.md` | 16 | `grep -c`, learnings file write paths |
| `plugins/soleur/agents/engineering/research/learnings-researcher.md` | 29 | 13 category paths, grep/ls commands |
| `plugins/soleur/commands/sync.md` | 5 | `mkdir -p` creates directories at legacy paths |

**Medium priority -- descriptive references agents can adapt around:**

| File | Count | Notes |
|---|---|---|
| `plugins/soleur/skills/plan/SKILL.md` | 24 | `ls -la`, output path examples, spec dir paths |
| `plugins/soleur/skills/brainstorm/SKILL.md` | 10 | Output paths, git add commands |
| `plugins/soleur/skills/ship/SKILL.md` | 8 | Glob patterns, git log paths |
| `plugins/soleur/skills/compound-capture/references/yaml-schema.md` | 13 | Category-to-directory mapping table |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | 4 | Learnings path references |
| `plugins/soleur/skills/spec-templates/SKILL.md` | 3 | Spec directory convention |
| `plugins/soleur/skills/merge-pr/SKILL.md` | 3 | Artifact discovery paths |
| `plugins/soleur/skills/archive-kb/SKILL.md` | 3 | Documentation table (legacy column) |
| `plugins/soleur/skills/work/SKILL.md` | 2 | Spec/tasks.md paths |
| `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` | 2 | Interface contract path |
| `plugins/soleur/skills/compound-capture/assets/critical-pattern-template.md` | 2 | Template paths |
| `plugins/soleur/skills/one-shot/SKILL.md` | 1 | Session-state.md path |
| `plugins/soleur/skills/brainstorm-techniques/SKILL.md` | 1 | Output location |
| `plugins/soleur/skills/compound-capture/assets/resolution-template.md` | 1 | Related problems link |
| `plugins/soleur/agents/product/cpo.md` | 1 | Spec path reference |
| `plugins/soleur/agents/engineering/infra/infra-security.md` | 1 | Learnings path |
| `AGENTS.md` | 1 | Constitution path in intro (this one is actually correct -- constitution.md stays at `knowledge-base/project/`) |

**AGENTS.md note:** The single reference in AGENTS.md (`knowledge-base/project/constitution.md`) is correct because constitution.md remains at that path. No change needed.

### Files NOT to Update

- `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` -- legacy paths are intentional fallback candidates (#602)
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- legacy paths are intentional fallback candidates (#602)
- Any reference to `knowledge-base/project/constitution.md` -- file remains at this path
- Any reference to `knowledge-base/project/components/` -- directory remains at this path
- Any reference to `knowledge-base/project/README.md` -- file remains at this path

## Replacement Rules

Apply these four substitutions across all in-scope files:

1. `knowledge-base/project/learnings/` -> `knowledge-base/learnings/`
2. `knowledge-base/project/brainstorms/` -> `knowledge-base/brainstorms/`
3. `knowledge-base/project/plans/` -> `knowledge-base/plans/`
4. `knowledge-base/project/specs/` -> `knowledge-base/specs/`

**Edge case -- `sync.md` mkdir:** The `mkdir -p knowledge-base/project/{learnings,brainstorms,specs,plans} knowledge-base/project/components` line needs to become `mkdir -p knowledge-base/{learnings,brainstorms,specs,plans} knowledge-base/project/components` (components stays under project/).

**Edge case -- archive-kb SKILL.md table:** The legacy paths in the "What It Archives" table should be relabeled, not removed, since the shell scripts intentionally still search them as fallbacks.

## Non-goals

- Migrating actual files from `knowledge-base/project/{brainstorms,plans,specs,learnings}/` to top-level (tracked by #568 if ever needed)
- Removing the `knowledge-base/project/` directory
- Updating shell scripts (already done in #602)
- Modifying `knowledge-base/project/constitution.md` path references (correct as-is)

## Acceptance Criteria

- [ ] `grep -r 'knowledge-base/project/learnings/' plugins/soleur/ AGENTS.md` returns zero matches
- [ ] `grep -r 'knowledge-base/project/brainstorms/' plugins/soleur/ AGENTS.md` returns zero matches (excluding archive-kb.sh, worktree-manager.sh)
- [ ] `grep -r 'knowledge-base/project/plans/' plugins/soleur/ AGENTS.md` returns zero matches (excluding archive-kb.sh, worktree-manager.sh)
- [ ] `grep -r 'knowledge-base/project/specs/' plugins/soleur/ AGENTS.md` returns zero matches (excluding archive-kb.sh, worktree-manager.sh)
- [ ] References to `knowledge-base/project/constitution.md` remain unchanged
- [ ] References to `knowledge-base/project/components/` remain unchanged
- [ ] All 20 plugin `.md` files updated consistently

## Test Scenarios

- Given all replacements are applied, when running `grep -rn 'knowledge-base/project/(learnings|brainstorms|plans|specs)' plugins/soleur/ --include='*.md'`, then zero matches are returned
- Given the `sync.md` mkdir command is updated, when the sync command creates KB directories, then directories are created at `knowledge-base/{learnings,brainstorms,specs,plans}` (not under `project/`)
- Given `compound-capture/SKILL.md` executable code blocks are updated, when an agent copy-pastes the `find` or `grep -r` commands, then they search the correct current paths
- Given `learnings-researcher.md` category paths are updated, when the agent searches for learnings, then it searches `knowledge-base/learnings/` subdirectories (not `knowledge-base/project/learnings/`)

## Context

- KB restructure: #566, #569
- Bash script fix: #600, #602
- Related learning: `knowledge-base/learnings/2026-03-13-archive-kb-stale-path-resolution.md`
- Related learning: `knowledge-base/project/learnings/2026-03-13-stale-cross-references-after-kb-restructuring.md`
- Constitution principle (line 104): "When fixing a pattern across plugin files, search ALL `.md` files under `plugins/soleur/` -- not just the category that triggered the report"

## References

- Issue: #604
- KB restructure PRs: #566
- KB rename: #569
- Bash script fix PR: #602
