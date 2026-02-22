# Learning: Archiving slug extraction must match branch naming conventions

## Problem

Knowledge base archiving silently failed for 92 artifacts across 13 brainstorms, 38 plans, and 41 spec directories. The root cause was a slug extraction mismatch: `compound-capture` used `${current_branch#feat-}` (bash parameter expansion) which only strips the `feat-` prefix, but the repo convention uses `feat/` (slash) branches. The slash variant was never stripped, producing slugs like `feat/domain-leaders` instead of `domain-leaders`, causing all artifact glob matches to fail silently.

A secondary cause was that `cleanup-merged` in `worktree-manager.sh` only archived spec directories -- brainstorms and plans were never archived by the cleanup safety net.

## Solution

1. Replaced the bash code fence in `compound-capture/SKILL.md` with prose instructions listing all prefix variants (`feat/`, `feat-`, `fix/`, `fix-`), which also resolved a constitution violation (no shell variable expansion in `.md` files).
2. Extended `worktree-manager.sh` `cleanup_merged_worktrees()` with an `archive_kb_files()` helper function that archives brainstorms and plans matching the feature slug.
3. Fixed the shell slug extraction to strip all prefix variants (`feat-`, `fix-`, `feature-`) using sequential parameter expansions, not just `feat-`.
4. Archived all 92 orphaned artifacts in a single atomic `git mv` commit.

## Key Insight

When fixing a pattern mismatch bug, the fix itself can reproduce the same bug if the developer only thinks about the primary case. The initial worktree-manager.sh fix used `${safe_branch#feat-}` -- the exact same single-prefix bug being fixed in compound-capture. All 4 parallel review agents caught this independently, proving that multi-agent review is especially valuable when the bug class is "subtle repetition of the pattern being fixed."

A second insight: when a shell script converts branch names with `tr '/' '-'`, all slash-based prefixes collapse into hyphen-based ones. This means `feat/` and `feat-` become identical after the `tr`, but `fix/` becomes `fix-` which is a different prefix. Sequential stripping (`${var#feat-}`, `${var#fix-}`, `${var#feature-}`) handles all cases correctly because `tr` has already normalized the separator.

## Session Errors

- Initial implementation reproduced the exact bug being fixed (single-prefix slug extraction in worktree-manager.sh) -- caught by review agents before merge
- `feature/` prefix was listed in compound-capture slug extraction but omitted from branch detection condition, creating dead documentation -- caught by review agents

## Tags
category: logic-errors
module: knowledge-base-archiving
