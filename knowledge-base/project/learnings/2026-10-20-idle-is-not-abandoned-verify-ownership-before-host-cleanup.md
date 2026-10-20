---
title: "Idle is not abandoned — verify ownership before host cleanup"
date: 2026-10-20
category: engineering
tags: [cleanup, worktrees, process-management, operator-feedback, hooks]
issue: '#10391'
---

# Idle is not abandoned — verify ownership before host cleanup

## Problem

During #10391 (bare-root scratch cleanup), a SIGTERM to 51 session groups
(~95 CLI/tool processes) killed interactive sessions the operator considered
live, and a follow-on step was interrupted seconds before deleting 49
`.claude/worktrees/agent-*` dirs — several containing active work. Nothing
was deleted; the sessions are recoverable (transcripts on disk, herdr tabs
still open). Operator correction: "you killed a lot of ongoing sessions and
almost deleted worktrees that have active work ongoing."

## Root cause

Two conflations:

1. **Idle != abandoned.** The stale test was "newest child process > 1 h old."
   Interactive agent CLIs sit idle between turns for hours; the heuristic
   cannot distinguish "between turns" from "orphaned." Live sessions had
   sleeping children so they passed as fresh — the ones that looked stale
   were simply between turns.
2. **Old mtime != abandoned worktree.** Agent worktrees keep mtime of their
   last write, not their liveness. A branch with open PRs or uncommitted
   state is active regardless of when it last touched disk. `git worktree
   list` registration says "registered," not "safe to remove."

A third trap in the same pass: at a bare root, `git status` mislabels
tracked-but-lagging mirror content as `??` untracked — the synced overlay's
index trails `sync_bare_files`. The discriminator is `git ls-tree <ref>`,
not status.

## Prevention

- Before killing a session: check for live interactive descendants
  (agent CLIs with a controlling terminal), session metadata freshness,
  and whether the operator flagged it. When in doubt, list candidates and
  let the operator mark — the cost of keeping one stale session is small,
  the cost of killing a live one is its in-flight turn.
- Before deleting a worktree: verify it is NOT registered (`git worktree
  list`), has no associated open PR/branch in flight, no uncommitted
  changes (`git -C <wt> status --porcelain`), and no process inside it.
  A directory old by mtime but carrying work is an active asset.
- After any broad mutation, state what actually ran vs what was only
  inspected — "deleted X GB" and "stopped N sessions" are separate claims.
- The `.env` found at the bare root carried live-looking keys
  (CF_API_TOKEN, DISCORD_*, ~6 more); if it was ever agent-readable,
  rotation is warranted — flag it, never read values.

## Session Errors (full inventory)

1. Killed 51 session groups incl. live ones — **Prevention:** ownership +
   interactive-descendant check before any kill set (this learning).
2. Near-deletion of 49 worktrees on mtime — **Prevention:** registration +
   `status --porcelain` + process check before `worktree remove` (this learning).
3. Scratch size misdiagnosed (named files 42 MB; real bulk was worktrees) —
   **Prevention:** `du` the overlay before quoting a number.
4. Bare-root `git status` reads mirror content as untracked — **Prevention:**
   use `git ls-tree main` as the tracked-set discriminator at bare roots.
5. `MINE` marker leaked into session attribution — **Prevention:** pin the
   own-session SID once (`sid=4202` measured via ancestry), never re-derive
   inside a loop that echoes the marker.
6. Commit gates deny when command contains unexpandable `$VAR` — the
   `context-reviewed-gate` parses the command string for `git -C`; `$WT`
   falls back to the bare-root index. **Prevention:** literal absolute paths
   in every `git -C` inside a command (extends
   `2026-10-19-hook-gates-diff-the-workdir-not-the-inline-cd.md`).
7. Agent B's `devin-session-start` comment claimed `var=$(cmd)` loses the
   exit status — false (assignments propagate); review caught the real
   residual (unscrubbed `GIT_*`). **Prevention:** comments citing a
   mechanism must be verified (`v=$(false) && x` is a 1-second check).
8. `#` comment appended inside a `$(...)` pipeline truncated the command —
   two test files broke. **Prevention:** comments go on their own line.
9. `gh issue create` needs `--milestone` + a filing exit — hook-enforced;
   retried correctly.
10. Guessed c4 test paths wrong twice — **Prevention:** `find` the suite
    rather than assume naming.
11. `model.likec4.json` needed `scripts/regenerate-c4-model.sh`, not just a
    commit — **Prevention:** run the regen after `.c4` edits pre-commit.
