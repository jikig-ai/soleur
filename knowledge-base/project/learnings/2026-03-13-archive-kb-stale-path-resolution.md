---
title: "Archive-KB and Worktree-Manager Stale Path Resolution"
date: 2026-03-13
category: workflow-issues
tags: [shell-scripting, knowledge-base, path-hardcoding, archive-kb, worktree-manager, migration-debt]
module: plugins/soleur/skills/archive-kb, plugins/soleur/skills/git-worktree
---

# Learning: Archive-KB and Worktree-Manager Stale Path Resolution

## Problem

After the knowledge-base restructure (#566, #568), artifacts moved from `knowledge-base/project/` subdirectories to top-level paths:

- `knowledge-base/project/brainstorms/` -> `knowledge-base/project/brainstorms/`
- `knowledge-base/project/plans/` -> `knowledge-base/project/plans/`
- `knowledge-base/project/specs/` -> `knowledge-base/project/specs/` and `knowledge-base/features/specs/`

Two shell scripts still hardcoded the legacy `knowledge-base/project/` prefixes:

1. **`archive-kb.sh`** -- `discover_artifacts()` searched only three legacy paths (`knowledge-base/project/brainstorms/`, `knowledge-base/project/plans/`, `knowledge-base/project/specs/`). After the restructure, it silently reported "No artifacts found" for every feature, even when brainstorms, plans, and specs existed at the new locations.

2. **`worktree-manager.sh`** -- `cleanup_merged_worktrees()` hardcoded `knowledge-base/project/specs/` for archiving and `knowledge-base/project/brainstorms/` and `knowledge-base/project/plans/` for `archive_kb_files()` calls. `create_for_feature()` created new spec directories at the legacy path. Both functions silently skipped artifacts at current paths.

The failure mode was silent: no errors, no warnings, just "No artifacts found" when artifacts existed. This meant merged features left unarchived artifacts scattered across the knowledge base.

## Solution

Replaced hardcoded single-path lookups with directory arrays that search current paths first, then legacy paths:

**archive-kb.sh `discover_artifacts()`:**

```bash
local file_dirs=(
  "knowledge-base/brainstorms"
  "knowledge-base/project/brainstorms"
  "knowledge-base/plans"
  "knowledge-base/project/plans"
)
for dir in "${file_dirs[@]}"; do
  for f in "$dir"/*"${slug}"*; do
    [[ -f "$f" && "$f" != */archive/* ]] && artifacts+=("$f")
  done
done

local spec_dirs=(
  "knowledge-base/specs"
  "knowledge-base/features/specs"
  "knowledge-base/project/specs"
)
for dir in "${spec_dirs[@]}"; do
  if [[ -d "$dir/feat-${slug}" ]]; then
    artifacts+=("$dir/feat-${slug}")
  fi
done
```

**worktree-manager.sh `cleanup_merged_worktrees()`:**

- Spec archiving iterates over a `spec_candidates` array (current + legacy paths), archiving into a sibling `archive/` directory relative to where the spec was found (using `dirname`).
- `archive_kb_files()` calls doubled: each legacy path call paired with the equivalent current path call.

**worktree-manager.sh `create_for_feature()`:**

- Updated to create new specs at `knowledge-base/project/specs/` only (the current canonical path). No reason to create at the legacy path.

`nullglob` (already set in `discover_artifacts()`) handles nonexistent directories gracefully -- empty globs expand to nothing rather than producing literal glob strings.

## Key Insight

Directory restructures create invisible breakage in shell scripts that construct paths from string literals. The scripts had no test coverage and no runtime validation that the paths they searched actually existed. The failure was silent because `for f in nonexistent-dir/*; do` with `nullglob` simply iterates zero times -- correct behavior for the shell, incorrect behavior for the user.

The fix pattern -- array of candidate paths with current-first ordering -- is the right approach when a codebase must support both pre-migration and post-migration layouts during a transition period. It avoids a hard cutover (which would break any in-flight worktrees with specs at legacy paths) while ensuring new artifacts are created at the canonical location.

Filed #604 to track broader SKILL.md reference cleanup for stale `knowledge-base/project/` paths in documentation across the repository.

## Tags

category: workflow-issues
module: plugins/soleur/skills/archive-kb, plugins/soleur/skills/git-worktree
