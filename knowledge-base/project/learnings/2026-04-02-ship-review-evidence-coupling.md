# Learning: Ship review-evidence detection breaks when artifact storage changes

## Problem

PR #1329 moved review findings from local `todos/` files to GitHub issues with the `code-review` label. The ship skill's review-evidence detection (Phase 1.5, Phase 5.5) and the pre-merge hook (Guard 6) still looked for only two signals -- both false-negating on post-#1329 branches. This caused ship to abort or force redundant re-reviews on branches that had already been reviewed.

## Solution

Added a third detection signal: check for GitHub issues with `code-review` label referencing the current branch's PR number. The three signals are OR'd -- any one suffices. Legacy signals preserved for backward compatibility with older branches. The hook extracts the PR number from the `gh pr merge` command args via regex, falling back to branch-based PR lookup. Signal 3 fails open (network errors treated as no-output) but the overall gate fails closed (all 3 signals must be empty to block).

Additional fixes during review:

- Phase 5.5 duplicated Phase 1.5 instructions verbatim -- deduplicated to a reference
- Step 3a used `$(...)` command substitution despite SKILL.md no-substitution rule -- split into 3 sequential steps

## Key Insight

When changing where artifacts are stored (local files to remote issues), all detection logic downstream must be updated. The ship skill and pre-merge hook were tightly coupled to the old storage location. The coupling was documented (the hook references specific file paths and git-log patterns), but the downstream consumers were not updated when the source changed in #1329. Any migration of artifact storage should include a grep for all consumers of the old location before shipping.

## Session Errors

1. `setup-ralph-loop.sh` called with wrong path initially. **Prevention:** Verify script paths with `ls` before invoking, especially in worktree contexts where relative paths shift.
2. `shellcheck` not installed -- hook logic verified manually instead. **Prevention:** Add `shellcheck` to the dev environment setup or use an online validator. Manual shell review is error-prone for quoting and word-splitting issues.

## Tags

category: integration-issues
module: ship-skill, pre-merge-hook
