# Learning: Session-scoped state files via PPID for parallel session isolation

## Problem

The ralph loop state file (`.claude/ralph-loop.local.md`) was project-scoped -- one file per project. In a bare repo with worktrees, all Claude Code sessions resolve to the same project root via `git rev-parse --git-common-dir`. When one session had an active ralph loop, the stop hook in every parallel session found the state file and blocked exit, injecting stale loop prompts into unrelated sessions. This made parallel development workflows unusable whenever ralph loop was active in any single session.

Alternatives considered and rejected:

- **CLAUDE_SESSION_ID**: Does not exist as an environment variable. Claude Code exposes no session identifier to hooks.
- **UUID generated at loop start**: Circular -- the loop start skill would need to propagate the UUID to the stop hook, but there is no shared channel except the state file itself.
- **Worktree path hash**: Multiple sessions can operate on the same worktree (e.g., one session running tests while another edits). A worktree-scoped file would still collide.

## Solution

Made state files session-scoped using the parent process ID (`$PPID`):

1. **Filename**: `ralph-loop.<PPID>.local.md` instead of `ralph-loop.local.md`. Each Claude Code session gets its own stop-hook shell, whose `$PPID` is the Claude Code process. Two sessions on the same repo produce different PIDs and therefore different filenames.

2. **Environment variable override**: `RALPH_LOOP_PID` env var (defaults to `$PPID`) allows tests to inject a deterministic PID without coupling to the process tree. Tests set `RALPH_LOOP_PID=99999` and assert against `ralph-loop.99999.local.md`.

3. **Glob-based TTL cleanup**: Before checking its own session file, the stop hook runs `for f in .claude/ralph-loop.*.local.md; do ...` to find and remove all session files older than the 4-hour TTL. This cleans up orphans from crashed sessions regardless of which PID created them. The `rm` inside the loop uses `|| true` for race-condition idempotency (two sessions may try to clean the same orphan simultaneously).

4. **Gitignore**: Added `.claude/ralph-loop.*.local.md` pattern (the old `.claude/ralph-loop.local.md` pattern was already present but did not match the new glob-based filenames).

5. **Help text**: User-facing instructions in `setup-ralph-loop.sh` use the glob pattern (`ralph-loop.*.local.md`) for manual cleanup, while runtime code uses the specific PID-based filename.

## Key Insight

When multiple processes share a filesystem namespace (bare repo with worktrees, shared home directory, containerized workloads with mounted volumes), state files must be scoped to the process, not the project. `$PPID` is the simplest correct identifier because it is always available, unique per parent process, and stable for the lifetime of the child shell. The general pattern is:

```
<state-name>.<process-identifier>.<extension>
```

Combined with glob-based TTL cleanup (`for f in <state-name>.*.ext`), this gives you: (a) session isolation -- each process reads/writes only its own file, (b) orphan recovery -- any process can clean up stale files from crashed siblings, and (c) testability -- inject a fake identifier via environment variable.

This is preferable to lock files or advisory locks because lock files have the same orphan problem (crashed process leaves lock), and `flock` does not work across NFS or in all container runtimes. The TTL-based glob cleanup is a distributed garbage collector that requires no coordination between processes.

## Session Errors

1. **Worktree created on wrong branch** -- `git worktree add` defaulted to an unexpected branch. Required manual `git checkout` inside the worktree to switch to the correct feature branch. Prevention: always specify `-b <branch>` or verify branch after creation.

2. **Plan assumed .gitignore already covered new filenames** -- The existing `.gitignore` rule was for the exact filename `ralph-loop.local.md`, not the glob `ralph-loop.*.local.md`. The plan said "no gitignore change needed" but the new filenames were not ignored. Prevention: when changing a filename pattern, always verify gitignore rules match the new pattern.

3. **Plan specified updating one-shot/SKILL.md** -- The plan listed a file edit for `plugins/soleur/skills/one-shot/SKILL.md`, but that file contained no reference to the state filename. The edit was a no-op. Prevention: before implementing plan-prescribed file edits, verify the target file actually contains the text to be changed (same class of error as path-tracing in AGENTS.md).

4. **`gh issue create` failed with invalid label** -- Used `type/refactor` label which does not exist in the repository. Changed to `type/chore`. Prevention: run `gh label list` before applying labels, or use labels known to exist from recent PRs.

## Cross-References

- `knowledge-base/project/learnings/2026-03-09-ralph-loop-crash-orphan-recovery.md` -- Original single-file TTL fix that this feature extends to per-session files
- `knowledge-base/project/learnings/bug-fixes/2026-03-13-ralph-loop-idle-detection-and-repetition.md` -- Idle/repetition detection that runs after the session-scoped state file is loaded
- `knowledge-base/project/learnings/2026-03-15-env-var-post-guard-defense-in-depth.md` -- Same environment-variable injection pattern used for testability
- `knowledge-base/project/learnings/2026-03-13-bare-repo-stale-files-and-working-tree-guards.md` -- Bare repo context that causes the shared project root
- GitHub issue #650 -- The bug report for parallel session blocking

## Tags

category: runtime-errors
module: ralph-loop
issue: 650
