---
title: "chore: clean up stale knowledge-base/project/ references in SKILL.md files"
type: chore
date: 2026-03-13
issue: "#604"
semver: patch
deepened: 2026-03-13
---

# chore: clean up stale knowledge-base/project/ references in SKILL.md files

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 3 (Scope, Replacement Rules, Test Scenarios)

### Key Improvements

1. Discovered 5 additional files outside `plugins/soleur/` with stale references that the original plan missed -- total scope increases from 20 to 25 files
2. Added edge case for `knowledge-base/project/constitution.md` line 153 (specs convention path) -- this reference IS inside `knowledge-base/project/` but refers to the now-moved specs directory
3. Applied learning from `readme-self-references-missed-in-rename`: files INSIDE the directory being restructured also contain self-references that don't match simple grep scopes

### New Considerations Discovered

- `knowledge-base/project/components/knowledge-base.md` has 7 stale references including executable `grep` and `ls` commands with legacy paths -- same high-priority category as the plugin SKILL.md files
- `knowledge-base/project/constitution.md` line 153 has a convention path `knowledge-base/project/specs/feat-<name>/` that should become `knowledge-base/project/specs/feat-<name>/`
- `knowledge-base/product/business-validation.md` references a brainstorm at the legacy path
- The grep verification commands in acceptance criteria must search the ENTIRE repo (not just `plugins/soleur/`), excluding `knowledge-base/project/` subdirectories that contain actual legacy content files (plans, brainstorms, specs, learnings still stored there)

## Overview

After the KB restructure (#566, #569), four artifact directories moved from `knowledge-base/project/` to top-level `knowledge-base/`:

| Legacy Path | Current Canonical Path |
|---|---|
| `knowledge-base/project/learnings/` | `knowledge-base/project/learnings/` |
| `knowledge-base/project/brainstorms/` | `knowledge-base/project/brainstorms/` |
| `knowledge-base/project/plans/` | `knowledge-base/project/plans/` |
| `knowledge-base/project/specs/` | `knowledge-base/project/specs/` |

Three paths under `knowledge-base/project/` remain correct and must NOT be changed:

- `knowledge-base/project/constitution.md` (stays)
- `knowledge-base/project/components/` (stays)
- `knowledge-base/project/README.md` (stays)

PR #602 fixed the two shell scripts (`archive-kb.sh`, `worktree-manager.sh`) that silently failed. This issue tracks the broader documentation cleanup: 154 stale references across 20 plugin `.md` files, plus 11 more across 5 knowledge-base documentation files.

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

**Knowledge-base documentation files (discovered during deepening):**

| File | Count | Notes |
|---|---|---|
| `knowledge-base/project/components/knowledge-base.md` | 7 | `grep`, `ls` commands and directory listing with legacy paths |
| `knowledge-base/project/constitution.md` | 1 | Convention path `knowledge-base/project/specs/feat-<name>/` on line 153 |
| `knowledge-base/project/README.md` | 1 | Specs path in directory description |
| `knowledge-base/project/components/agents.md` | 1 | Learnings-researcher path in agent table |
| `knowledge-base/product/business-validation.md` | 1 | Brainstorm cross-reference |

### Research Insights

**Learning applied -- `readme-self-references-missed-in-rename`:** When planning a directory restructure cleanup, enumerate ALL files in the affected directory as potential self-reference holders. The original plan scoped only `plugins/soleur/` files but the `knowledge-base/project/` directory itself contains documentation files with executable code snippets referencing the old structure.

**Learning applied -- `sed-insertion-fails-silently`:** After batch replacements, verify changes landed with `grep -rL` (list files NOT matching expected pattern) or `grep -c` (count remaining stale references). Silent failures in batch operations are the primary risk for this task.

### Files NOT to Update

- `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` -- legacy paths are intentional fallback candidates (#602)
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- legacy paths are intentional fallback candidates (#602)
- Any reference to `knowledge-base/project/constitution.md` -- file remains at this path
- Any reference to `knowledge-base/project/components/` -- directory remains at this path
- Any reference to `knowledge-base/project/README.md` -- file remains at this path
- `knowledge-base/project/plans/` content files -- these are actual plan documents stored at the legacy path, not stale references
- `knowledge-base/project/brainstorms/` content files -- same, actual content at legacy path
- `knowledge-base/project/learnings/` content files -- same, actual content at legacy path
- `knowledge-base/project/specs/` content files -- same, actual content at legacy path
- `knowledge-base/project/specs/feat-fix-archive-kb-paths/` -- historical records describing what was done in #602
- `knowledge-base/project/plans/2026-03-13-fix-archive-kb-stale-paths-plan.md` -- references legacy paths in context section (historical)
- `knowledge-base/project/learnings/2026-03-13-archive-kb-stale-path-resolution.md` -- documents the problem (historical)

## Replacement Rules

Apply these four substitutions across all in-scope files:

1. `knowledge-base/project/learnings/` -> `knowledge-base/project/learnings/`
2. `knowledge-base/project/brainstorms/` -> `knowledge-base/project/brainstorms/`
3. `knowledge-base/project/plans/` -> `knowledge-base/project/plans/`
4. `knowledge-base/project/specs/` -> `knowledge-base/project/specs/`

**Edge case -- `sync.md` mkdir:** The `mkdir -p knowledge-base/project/{learnings,brainstorms,specs,plans} knowledge-base/project/components` line needs to become `mkdir -p knowledge-base/{learnings,brainstorms,specs,plans} knowledge-base/project/components` (components stays under project/).

**Edge case -- archive-kb SKILL.md table:** The legacy paths in the "What It Archives" table should be relabeled, not removed, since the shell scripts intentionally still search them as fallbacks.

**Edge case -- constitution.md line 153:** The convention rule `feat-<name>` maps to `knowledge-base/project/specs/feat-<name>/` contains a specs path reference. This is a special case: the file itself lives at `knowledge-base/project/constitution.md` (correct), but the convention path it describes points to the legacy specs location. Update the specs path portion only: `knowledge-base/project/specs/feat-<name>/`.

**Edge case -- business-validation.md line 54:** Contains a `See knowledge-base/project/brainstorms/...` cross-reference. The actual brainstorm may still be at the legacy path. Verify the file exists at the new path before updating; if not, leave as-is (the reference points to real content that hasn't been migrated).

### Verification Strategy

After all replacements, run these commands to confirm completeness:

```bash
# Count remaining stale refs in plugin files (expect 0)
grep -rn 'knowledge-base/project/\(learnings\|brainstorms\|plans\|specs\)' plugins/soleur/ --include='*.md' | wc -l

# Count remaining stale refs in KB documentation files (expect 0)
grep -rn 'knowledge-base/project/\(learnings\|brainstorms\|plans\|specs\)' knowledge-base/project/constitution.md knowledge-base/project/README.md knowledge-base/project/components/ knowledge-base/product/ --include='*.md' | wc -l

# Confirm preserved references are intact
grep -c 'knowledge-base/project/constitution.md' plugins/soleur/skills/compound/SKILL.md plugins/soleur/skills/work/SKILL.md plugins/soleur/skills/plan/SKILL.md plugins/soleur/commands/sync.md
```

## Non-goals

- Migrating actual files from `knowledge-base/project/{brainstorms,plans,specs,learnings}/` to top-level (tracked by #568 if ever needed)
- Removing the `knowledge-base/project/` directory
- Updating shell scripts (already done in #602)
- Modifying `knowledge-base/project/constitution.md` path references (correct as-is)

## Acceptance Criteria

- [x] `grep -rn 'knowledge-base/project/\(learnings\|brainstorms\|plans\|specs\)' plugins/soleur/ --include='*.md'` returns zero matches (3 remaining are intentional legacy fallback docs in archive-kb/SKILL.md)
- [x] `grep -rn 'knowledge-base/project/\(learnings\|brainstorms\|plans\|specs\)' knowledge-base/project/constitution.md knowledge-base/project/README.md knowledge-base/project/components/ knowledge-base/product/ --include='*.md'` returns zero matches (1 remaining is dead ref in business-validation.md — brainstorm file doesn't exist at either path)
- [x] Shell scripts `archive-kb.sh` and `worktree-manager.sh` are NOT modified (legacy paths are intentional fallbacks)
- [x] References to `knowledge-base/project/constitution.md` remain unchanged across all files
- [x] References to `knowledge-base/project/components/` remain unchanged across all files
- [x] All 25 files (20 plugin + 5 KB docs) updated consistently (23 modified, 2 intentionally unchanged: archive-kb legacy docs, business-validation dead ref)
- [x] Total stale reference count drops from ~165 to 4 (3 intentional legacy docs + 1 dead ref)

## Test Scenarios

- Given all replacements are applied, when running `grep -rn 'knowledge-base/project/(learnings|brainstorms|plans|specs)' plugins/soleur/ --include='*.md'`, then zero matches are returned
- Given all replacements are applied, when running the same grep against `knowledge-base/project/constitution.md`, `knowledge-base/project/README.md`, `knowledge-base/project/components/`, and `knowledge-base/product/`, then zero matches are returned
- Given the `sync.md` mkdir command is updated, when the sync command creates KB directories, then directories are created at `knowledge-base/{learnings,brainstorms,specs,plans}` (not under `project/`)
- Given `compound-capture/SKILL.md` executable code blocks are updated, when an agent copy-pastes the `find` or `grep -r` commands, then they search the correct current paths
- Given `learnings-researcher.md` category paths are updated, when the agent searches for learnings, then it searches `knowledge-base/project/learnings/` subdirectories (not `knowledge-base/project/learnings/`)
- Given `knowledge-base/project/components/knowledge-base.md` is updated, when an agent reads the component documentation, then directory listings and grep commands point to current paths
- Given constitution.md convention path is updated, when the convention-over-configuration rule is applied, then `feat-<name>` maps to `knowledge-base/project/specs/feat-<name>/` (not the legacy path)
- Given references to `knowledge-base/project/constitution.md` are preserved, when counted with `grep -c`, then the count matches the pre-change baseline

## Context

- KB restructure: #566, #569
- Bash script fix: #600, #602
- Related learning: `knowledge-base/project/learnings/2026-03-13-archive-kb-stale-path-resolution.md`
- Related learning: `knowledge-base/project/learnings/2026-03-13-stale-cross-references-after-kb-restructuring.md`
- Constitution principle (line 104): "When fixing a pattern across plugin files, search ALL `.md` files under `plugins/soleur/` -- not just the category that triggered the report"

## References

- Issue: #604
- KB restructure PRs: #566
- KB rename: #569
- Bash script fix PR: #602
