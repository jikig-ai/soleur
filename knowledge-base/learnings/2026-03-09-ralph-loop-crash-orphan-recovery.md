# Learning: Ralph Loop State File Persists After Crash

## Problem

After a laptop crash mid-session, every new Claude Code session received spurious "finish all slash commands" feedback injected on every turn. The agent would attempt to wrap up and exit instead of responding to user input. The behavior recurred on every turn, making the session unusable.

## Investigation

1. Ran `worktree-manager.sh cleanup-merged && git worktree list` — 3 active worktrees with open WIP PRs, all intact
2. Checked `git status` on repo root — `.claude/ralph-loop.local.md` present as untracked file
3. Read `plugins/soleur/hooks/stop-hook.sh` — the stop hook checks for the state file on every session exit attempt (line 18). When the file exists with `active: true`, it outputs `"decision": "block"` and re-injects the loop prompt (lines 162-169)
4. The state file had `iteration: 6`, `stuck_count: 0`, and prompt text "finish all slash commands"

## Root Cause

The Ralph Loop uses `.claude/ralph-loop.local.md` as a semaphore. Under normal operation, the loop cleans up the state file when it terminates (max iterations, completion promise, stuck detection, or corrupted state). A laptop crash kills the process without running any cleanup. The state file persists on disk, and the next session's stop hook finds it, treats the loop as active, and blocks exit with the stale prompt.

Stuck detection (3 consecutive short responses) never fires because the injected prompt produces substantive output each time — the agent attempts to comply with "finish all slash commands."

## Solution

Remove the stale state file:

```bash
rm .claude/ralph-loop.local.md
```

## Prevention

The stop hook should detect stale state files using the existing `started_at` timestamp. A loop older than 4 hours is almost certainly a crash orphan. Implementation belongs in the `feat-fix-ralph-loop-stop-hook` worktree alongside the other stop hook fixes (PR #465).

## Key Insight

Filesystem-based semaphores (state files) are not crash-safe. Any system that uses a file as a "loop is active" signal must have a staleness check or the file will outlive the process that created it. The Ralph Loop's `started_at` field already provides the data needed for a TTL — the stop hook just needs to check it.

## Session Errors

1. Stale Ralph Loop state file caused stop hook to fire on every turn, injecting "finish all slash commands" — required reading stop-hook.sh source to diagnose

## Cross-References

- `knowledge-base/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md` — stuck detection mechanism
- `knowledge-base/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md` — frontmatter parsing in stop hook
- PR #465 (`feat/fix-ralph-loop-stop-hook`) — planned stop hook fixes

## Tags

category: workflow
module: ralph-loop
