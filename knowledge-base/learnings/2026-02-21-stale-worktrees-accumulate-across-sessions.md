# Learning: Stale worktrees accumulate across sessions

## Problem

After multiple sessions, 4 worktrees had accumulated -- 3 with already-merged PRs and 1 with no PR. PR #170 was fully ready to merge (CI passing, no conflicts, not draft) but had been left open. The worktrees contained leftover temp files (screenshots, package-lock changes) that went unnoticed.

## Symptoms

- `git worktree list` shows 4+ worktrees, most for branches whose PRs are already merged
- Open PRs that are fully ready to merge but were never merged (session ended before step 10)
- Stale temp files (screenshots, `.png`, `package-lock.json` diffs) accumulating in worktree directories

## Root Cause

The Workflow Completion Protocol (AGENTS.md step 10) bundles merge and cleanup as a single step. When a session ends after merge but before `cleanup-merged` runs -- or before merge entirely (as with PR #170) -- the worktree becomes orphaned. There was no session-start check to detect and clean up stale worktrees from prior sessions.

The existing learning from 2026-02-09 identified this gap and added Phase 8 to `/ship`, but the fundamental issue persisted: cleanup only ran if `/ship` was used AND the session survived long enough to reach Phase 8. PRs merged via GitHub UI, manual `gh pr merge`, or sessions that ended prematurely all left worktrees behind.

## Solution

Added a **Session-Start Hygiene** section to AGENTS.md that runs `cleanup-merged` at the start of every session before any other work. This is the recovery mechanism -- it catches any worktrees that were orphaned by prior sessions regardless of how the PR was merged.

Supporting changes:
- Updated AGENTS.md step 10 to name the merge-then-session-end gap explicitly
- Added constitution rule enforcing session-start cleanup
- Added safety note to ship/SKILL.md Phase 8 about deferred cleanup being handled by the next session

## Key Insight

Session boundaries are the most common point of workflow failure. Any step that depends on being "the last thing in a session" will eventually be skipped. The fix is not to make the last step more reliable -- it is to add a recovery mechanism at the start of the next session. The `cleanup-merged` script was already idempotent and safe; the only missing piece was a trigger at session start.

## Related

- `2026-02-09-worktree-cleanup-gap-after-merge.md` -- original identification of the trigger gap
- `2026-02-17-worktree-not-enforced-for-new-work.md` -- related worktree discipline gap
- `2026-02-19-never-use-delete-branch-with-parallel-worktrees.md` -- `--delete-branch` prohibition

## Tags

category: workflow-issues
module: git-worktree, ship, session-management
symptoms: stale worktree, orphaned worktree, PR not merged, temp files in worktree
