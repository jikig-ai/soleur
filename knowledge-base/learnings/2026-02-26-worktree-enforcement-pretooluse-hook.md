# Learning: Worktree Write Guard — Enforce File Isolation via PreToolUse Hook

## Problem

Agents repeatedly write files (screenshots, knowledge-base artifacts, temp analysis) to the main repo checkout instead of the active worktree, despite AGENTS.md hard rules stating "Never edit files in the main repo when a worktree is active." Documentation-only rules are insufficient — agents violate them under complex reasoning chains.

Secondary issue: `cleanup_merged_worktrees()` used `git status --porcelain` which includes untracked files, causing the post-cleanup `git pull` to be skipped whenever screenshots or temp artifacts existed in the main checkout.

## Solution

### PreToolUse Hook (`worktree-write-guard.sh`)

Created a hook that intercepts `Write` and `Edit` tool calls before execution. Key design:

- Uses `git rev-parse --git-common-dir` to reliably find the main repo root (works from both main checkout and worktrees)
- Allows: writes outside the repo, writes inside `.worktrees/`, writes to `.claude/` (settings, hooks, memory)
- Blocks: any write to the main repo checkout when `.worktrees/` directory contains active worktrees
- Returns actionable error: shows the correct worktree path the agent should use instead

Registered in `.claude/settings.json` with matcher `Write|Edit`.

### cleanup-merged Fix

Replaced `git status --porcelain` with `git diff --quiet HEAD` + `git diff --cached --quiet` to only check tracked file changes. Untracked files cannot conflict with a fast-forward pull and should not block the update.

## Key Insight

**Hook-based enforcement > documentation-based rules.** PreToolUse hooks make violations impossible rather than aspirational. This is the same pattern as `guardrails.sh` (which blocks `git commit` on main), extended to file write operations. The progression: Guard 1 (commit on main) → Guard 2 (rm -rf worktrees) → Guard 3 (--delete-branch with worktrees) → Guard 4 (write to main with worktrees active).

For `git status --porcelain` checks that gate further operations: consider whether untracked files actually conflict with the gated operation. For fast-forward pulls, they don't.

## Related Learnings

- `2026-02-24-guardrails-chained-commit-bypass.md` — Guard 1 pattern matching lessons
- `2026-02-24-guardrails-grep-false-positive-worktree-text.md` — Guard 2 false positive fix
- `2026-02-17-worktree-not-enforced-for-new-work.md` — Why worktree enforcement is a hard rule
- `2026-02-22-worktree-loss-stash-merge-pop.md` — Consequences of improper worktree state management
- `2026-02-21-stale-worktrees-accumulate-across-sessions.md` — Why cleanup-merged runs at session start

## Tags
category: integration-issues
module: git-worktree, guardrails
