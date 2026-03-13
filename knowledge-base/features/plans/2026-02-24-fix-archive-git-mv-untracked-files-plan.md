---
title: "fix: Make archive git mv resilient to untracked files"
type: fix
date: 2026-02-24
deepened: 2026-02-24
---

# fix: Make archive git mv resilient to untracked files

## Enhancement Summary

**Deepened on:** 2026-02-24
**Sections enhanced:** 4 (Root Cause, Solution, Implementation, Edge Cases)
**Research sources:** Local codebase grep (all `git mv` in `plugins/soleur/**/*.md`), 3 relevant learnings, constitution review

### Key Improvements

1. Added edge case: `git mv` on a file staged but not committed also fails -- `git add` is already satisfied, so the fallback must check tracking status, not just staging
2. Identified that compound-capture Step E's trailing fallback note is a known LLM attention pattern failure -- preamble instructions are more reliable than trailing notes
3. Confirmed via exhaustive grep that exactly 4 files are affected (no hidden instances in reference docs or other skills)

### New Considerations Discovered

- The fallback instruction wording must be unambiguous about *when* to run `git add` -- only when `git mv` fails, not unconditionally (unconditional `git add` before `git mv` would stage unrelated changes if the file is in a dirty worktree)
- The compound-capture SKILL.md Step F already runs `git add -A knowledge-base/` after archival, which would stage everything including half-moved files if `git mv` fails mid-sequence -- the fallback should be per-artifact, not batch

## Problem

`git mv` fails with `fatal: not under version control` when archiving knowledge-base files that were created during the current session but never committed. This is a recurring issue (#290) that breaks the compound-capture archival flow and any skill that archives KB artifacts.

The error from the issue:

```text
fatal: not under version control,
source=knowledge-base/plans/2026-02-24-fix-competitive-landscape-tables-and-tiers-plan.md,
destination=knowledge-base/plans/archive/20260224-081609-2026-02-24-fix-competitive-landscape-tables-and-tiers-plan.md
```

## Root Cause

The constitution mandates `git mv` for all KB file moves to preserve history. However, files created during a feature branch session (brainstorms, plans, specs) may not yet be committed when archival runs. `git mv` requires the source file to be tracked (committed at least once). Untracked files cause a fatal error that halts the archival flow.

The compound-capture skill (line 446) already has a workaround note: "If `git mv` fails (untracked file), run `git add` on the file first, then retry the `git mv`." But:

1. This is an LLM instruction, not a shell guard -- the model may miss or skip it
2. Three other skills (`brainstorm/SKILL.md`, `plan/SKILL.md`, `compound/SKILL.md`) have no such fallback
3. The worktree-manager.sh script uses plain `mv` (correct, since it runs from the main repo on already-merged branches), but skills that archive during active work use `git mv` without the safety net

### Research Insights

**Why this keeps recurring:** The learning `2026-02-22-command-substitution-in-plugin-markdown.md` documents a pattern where fixes to plugin markdown files are scoped too narrowly -- each fix catches the files known at the time but misses others. The same pattern applies here: compound-capture got the fallback, but brainstorm/plan/compound did not. The fix must search the widest scope (`plugins/soleur/**/*.md`) and patch all instances.

**Verified exhaustive search:** `grep -rn 'git mv' plugins/soleur/ --include='*.md'` confirms exactly 4 actionable locations (the CHANGELOG.md mentions are descriptive, not instructional). No hidden instances exist in reference docs, agent files, or other skills.

## Affected Files

| File | Location of `git mv` archive instruction | Current fallback |
|------|----------------------------------------|-----------------|
| `plugins/soleur/skills/compound-capture/SKILL.md` | Lines 425-446 (Step E: Archival) | Partial: trailing note at line 446 says "If git mv fails, git add first" |
| `plugins/soleur/skills/brainstorm/SKILL.md` | Line 280 (Archive old brainstorms) | None |
| `plugins/soleur/skills/plan/SKILL.md` | Line 392 (Archive completed plans) | None |
| `plugins/soleur/skills/compound/SKILL.md` | Line 181 (Archive an outdated learning) | None |

## Solution

Replace bare `git mv` instructions in all 4 skill files with a robust two-step pattern: attempt `git mv` first; if it fails, fall back to `git add` + `git mv`.

### Pattern

For inline archive instructions (brainstorm, plan, compound), the current pattern is a single inline command:

```text
mkdir -p knowledge-base/<type>/archive && git mv knowledge-base/<type>/<file>.md knowledge-base/<type>/archive/
```

Add a fallback sentence after each `git mv` instruction:

```text
If `git mv` fails with "not under version control", the file is untracked. Run `git add` on the source file first, then retry the `git mv`.
```

For the compound-capture SKILL.md (Step E), reposition the existing trailing note as a **preamble** before the three `git mv` blocks, so the model reads the rule before encountering each command.

### Research Insights

**Preamble vs. trailing note:** LLMs process instructions sequentially. A fallback rule positioned *after* three code blocks is less likely to be applied than one positioned *before* them. The compound-capture SKILL.md should move the fallback from a trailing `**If git mv fails**` paragraph (line 446) to a preamble sentence before line 431. This is consistent with how the skill already uses preamble instructions for the timestamp format (line 427).

**Per-artifact fallback, not batch:** The `git add` must target only the specific source file, not a broad `git add -A`. If `git mv` fails on the first artifact, running `git add -A` would stage all untracked files in `knowledge-base/`, not just the one being archived. The fallback must be: `git add <specific-source-path>`, then retry `git mv <specific-source-path> <destination-path>`.

## Acceptance Criteria

- [x] All 4 skill files include the `git add` fallback instruction adjacent to every `git mv` archive command
- [x] compound-capture/SKILL.md Step E has the fallback as a preamble (before the `git mv` blocks), not a trailing note
- [x] The fallback instructs `git add` on the specific source file only (not `git add -A` or `git add .`)
- [x] No new files created -- edits only to existing .md files
- [x] `bun test` passes (no source code changes, but verify nothing breaks)
- [x] markdownlint passes on all modified files

## Test Scenarios

- Given an untracked plan file created this session, when compound-capture archives it, then `git add` runs on the specific file first and `git mv` succeeds
- Given a tracked (committed) brainstorm file, when brainstorm skill archives it, then `git mv` succeeds directly without needing `git add`
- Given an untracked learning file, when compound skill archives it, then the fallback instruction is followed and the file moves to archive/
- Given a compound-capture run with 3 artifacts (1 tracked, 2 untracked), when Step E runs, then the tracked file moves with `git mv` directly and the 2 untracked files each get `git add` + `git mv` individually

## Non-Goals

- Changing worktree-manager.sh -- it correctly uses plain `mv` for post-merge cleanup
- Adding shell scripts or helper functions -- the fix is prose instruction changes in skill .md files
- Changing the constitution's `git mv` mandate -- `git mv` is still the right tool, it just needs a pre-step for untracked files
- Adding a shell wrapper function for `git mv` -- the skills are LLM instructions, not executable scripts

## Implementation

### 1. compound-capture/SKILL.md (Step E: Archival)

**Current** (lines 425-446): The fallback is a trailing paragraph after all three `git mv` code blocks.

**Change:** Remove the trailing `**If git mv fails**` paragraph (line 446). Add a preamble sentence before the first `git mv` block (after line 429, before line 431):

```text
For each artifact, attempt `git mv`. If it fails with "not under version control", the file is untracked -- run `git add` on the specific source file first, then retry the `git mv`.
```

This single preamble applies to all three subsequent `git mv` blocks.

### 2. brainstorm/SKILL.md (Archive old brainstorms)

**Current** (line 280): Single inline sentence with `git mv`.

**Change:** Append after the existing sentence: `If git mv fails with "not under version control", run git add on the source file first, then retry.`

### 3. plan/SKILL.md (Archive completed plans)

**Current** (line 392): Single inline sentence with `git mv`.

**Change:** Same as brainstorm -- append fallback sentence.

### 4. compound/SKILL.md (Archive an outdated learning)

**Current** (line 181): Single inline sentence with `git mv`.

**Change:** Same as brainstorm -- append fallback sentence.

## Edge Cases

### File staged but not committed

If a file has been `git add`-ed but not committed, `git mv` works correctly (the index entry is sufficient). The fallback `git add` is a no-op in this case. No special handling needed.

### Partial failure mid-sequence (compound-capture)

If Step E archives 2 of 3 artifacts successfully and the 3rd fails, the first 2 are already moved. Step F's `git add -A knowledge-base/` will stage everything correctly. The fallback runs per-artifact so partial progress is preserved.

### Spec directories (not files)

The compound-capture Step E archives spec *directories*, not individual files. `git mv` on a directory works if any file inside is tracked. If the entire spec directory is untracked (e.g., only contains a tasks.md that was never committed), `git add <dir>` then `git mv <dir>` handles this correctly.

## Version Bump

PATCH bump (bug fix in existing skill instructions). Update `plugin.json`, `CHANGELOG.md`, and `README.md`.

## Rollback Plan

Revert the single commit. The `git mv` commands still work for tracked files; the fallback is additive and has no side effects when not triggered.

## References

- Issue: #290
- Learning: `knowledge-base/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`
- Learning: `knowledge-base/learnings/2026-02-22-command-substitution-in-plugin-markdown.md` (search scope pattern)
- Learning: `knowledge-base/learnings/2026-02-22-cleanup-merged-path-mismatch.md` (worktree-manager context)
- Constitution rule: "Operations that modify the knowledge-base or move files must use `git mv` to preserve history"
