---
title: "fix: ralph loop stop hook blocks all parallel sessions on same repo"
type: fix
date: 2026-03-17
issue: "#650"
---

# fix: ralph loop stop hook blocks all parallel sessions on same repo

## Overview

The ralph loop state file (`$PROJECT_ROOT/.claude/ralph-loop.local.md`) is project-scoped. Since all worktrees in a bare repo share the same project root (resolved via `git rev-parse --git-common-dir`), a ralph loop active in one Claude Code session blocks exit in **all** parallel sessions on the same repo. Session B enters an infinite loop of stop hook rejections because it finds session A's state file.

## Root Cause

Both `stop-hook.sh` and `setup-ralph-loop.sh` resolve to a single state file path:

```bash
# plugins/soleur/hooks/stop-hook.sh:21
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"

# plugins/soleur/scripts/setup-ralph-loop.sh:143
cat > "${PROJECT_ROOT}/.claude/ralph-loop.local.md" <<EOF
```

There is no session identifier in the filename. Any session that shares the same `PROJECT_ROOT` sees the same state file.

## Proposed Solution: PPID-based session scoping

Use `$PPID` (parent process ID of the hook/script) to scope state files per session. Claude Code spawns each hook as a child process, so `$PPID` is the Claude Code process PID -- stable within a session, unique across parallel sessions.

### Why PPID over alternatives

| Approach | Pros | Cons |
|----------|------|------|
| `$PPID` | Available in all bash, stable per session, unique across parallel sessions | Orphaned files on crash (mitigated by existing TTL) |
| `$CLAUDE_SESSION_ID` | Semantically perfect | Does not exist in the hook environment (verified) |
| Random UUID at setup time | Guaranteed unique | Requires passing the UUID from setup to stop hook via state file, circular |
| Worktree path hash | Scoped per worktree | Two sessions on the same worktree still collide |

PPID is the only reliable, environment-available, session-stable identifier. The existing TTL check (1-hour auto-remove) already handles orphaned state files from crashed sessions, so PID reuse is not a concern in practice.

### State file naming

```
# Before (project-scoped):
.claude/ralph-loop.local.md

# After (session-scoped):
.claude/ralph-loop.<PPID>.local.md
```

Example: `.claude/ralph-loop.12345.local.md`

### Gitignore

The existing `.claude/*.local.md` pattern in `.gitignore` already covers PID-suffixed files via the glob. No gitignore changes needed.

## Acceptance Criteria

- [ ] `setup-ralph-loop.sh` creates session-scoped state file at `$PROJECT_ROOT/.claude/ralph-loop.<PPID>.local.md`
- [ ] `stop-hook.sh` reads/writes only the state file matching its own `$PPID`
- [ ] `stop-hook.sh` ignores state files from other sessions (does not block exit)
- [ ] TTL check still works on session-scoped files (stale file auto-removed)
- [ ] Cancel instructions in setup output reflect the new filename pattern (or use a glob)
- [ ] Existing tests pass after adapting to new file path
- [ ] New test: two state files from different PIDs do not interfere

## Test Scenarios

- Given session A starts a ralph loop, when session B (different PPID) tries to exit, then session B exits cleanly (no block)
- Given session A starts a ralph loop, when session A tries to exit, then the stop hook blocks and feeds prompt back (existing behavior)
- Given a stale session-scoped state file (older than TTL), when any session starts, then the stale file is auto-removed
- Given session A starts a ralph loop, when session A cancels (`rm .claude/ralph-loop.*.local.md`), then the loop stops
- Given a state file exists with PID 12345, when stop-hook runs with PPID 67890, then exit is allowed (file ignored)

## Affected Files

### `plugins/soleur/hooks/stop-hook.sh`

1. Change `RALPH_STATE_FILE` to include `$PPID`: `"${PROJECT_ROOT}/.claude/ralph-loop.${PPID}.local.md"`
2. Add glob-based TTL cleanup: before checking own state file, iterate over `ralph-loop.*.local.md` and remove any that exceed TTL. This handles orphaned files from crashed sessions regardless of PID.
3. Keep all other logic unchanged -- the hook only reads/writes its own session's file.

### `plugins/soleur/scripts/setup-ralph-loop.sh`

1. Change state file path to `"${PROJECT_ROOT}/.claude/ralph-loop.${PPID}.local.md"`
2. Update the cancel instructions in the output message to show the glob pattern: `rm .claude/ralph-loop.*.local.md` (or the specific PID file)
3. Update the monitoring instructions similarly

### `plugins/soleur/test/ralph-loop-stuck-detection.test.sh`

1. Update `create_state_file` to use `ralph-loop.$$.local.md` (test's own PID)
2. Update all direct references to `ralph-loop.local.md` in assertions
3. Add a new test: create a state file with a different PID, verify the hook ignores it and allows exit
4. Add a new test: verify TTL glob cleanup removes stale files from other PIDs

### `plugins/soleur/skills/one-shot/SKILL.md`

1. Update the `rm .claude/ralph-loop.local.md` cancel instruction to use the glob pattern

## Edge Cases

### PID reuse after reboot
A new session could get the same PPID as a previously crashed session. The TTL check (1-hour) handles this: if the old file is stale, it gets auto-removed before the new session's setup creates a fresh one.

### Multiple loops in same session
Not supported (existing limitation). Setup overwrites the previous state file for the same PPID. This is unchanged behavior.

### PPID stability across hook invocations
The stop hook is invoked as a child of the Claude Code process. `$PPID` in the hook is the Claude Code process PID, which is stable for the lifetime of the session. The setup script is also invoked as a child of the same Claude Code process. Both scripts see the same `$PPID`.

### Glob-based TTL cleanup performance
The `.claude/` directory is small (a handful of files). Iterating over `ralph-loop.*.local.md` with a for loop is negligible overhead.

## References

- Issue: #650
- `plugins/soleur/hooks/stop-hook.sh` -- stop hook (main affected file)
- `plugins/soleur/scripts/setup-ralph-loop.sh` -- loop setup script
- `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` -- test suite
- `knowledge-base/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md` -- related bare repo learning
