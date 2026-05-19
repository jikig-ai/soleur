---
name: worktree-recovery-check-pr-merge-status-first
description: Before recommending "reset to remote branch" to recover a stale worktree, verify the PR isn't already merged — the remote feature branch may be post-merge stale.
metadata:
  category: workflow-patterns
  module: git-worktree
  date: 2026-05-19
tags:
  - worktree
  - recovery
  - pr-status
---

## Problem

User asked to resume a worktree left in a broken state after a laptop crash. The worktree was on `main` (branch had been switched away) with 188 phantom staged files. The remote feature branch `origin/<feature>` still existed.

Initial reflex: recommend "Reset to remote branch" as the safe recovery — discard the stale index, check out the feature branch tracking the remote. This is the standard worktree-recovery move.

But the remote feature branch was 27 commits BEHIND main, and the user's commit message `fix(cla-evidence): bootstrap.sh requires real R2 S3 creds + probe-PUT before Doppler` had been squash-merged into main 12 hours earlier as commit `289489c3` with `(#3969)` suffix. PR #3969 was already MERGED.

Resetting the worktree to the stale remote branch would have looked like a clean recovery but actually reintroduced a pre-merge state — silently undoing the merge and inviting accidental "revert PR" follow-ups.

## Root Cause

Worktree-recovery instinct treats "remote branch still exists" as proof the work is unfinished. After a squash merge, the remote branch persists until manually deleted (GitHub's auto-delete-on-merge isn't always enabled), so its mere existence is not a signal that the feature is open.

The cheap merge-status signal was sitting in the reflog: commits on the remote branch with `(#NNNN)` suffix on their messages are squash-merge artifacts that the merge job committed back via "Merge origin/main into <branch>" syncs. That suffix is a free probe for "PR was merged."

## Solution

Before proposing reset-to-remote during worktree recovery:

```bash
gh pr list --head <branch> --state all --json number,title,state,url
```

If `state == MERGED`, the work is shipped. Recovery path becomes:
1. Reset/clean the worktree's index (`git reset --hard HEAD`)
2. Remove the worktree (`git worktree remove`)
3. Delete the stale remote branch (`git push origin --delete <branch>`)
4. Prune local refs (`git remote prune origin`)

If `state == OPEN`, reset-to-remote is the right call.

## Key Insight

A stale worktree post-laptop-crash carries no signal about whether the work is shipped. The branch existence on origin is a red herring — squash merges leave the source branch intact. Always probe PR status before assuming "remote branch == open work."

## Session Errors

- **CWD drift during destructive ops** — Ran `git reset --hard HEAD` from what looked like the bare root but was actually the worktree (persistent CWD from an earlier `cd`). Took 3 iterations to verify. **Prevention:** `pwd` before every `git reset --hard` in multi-worktree repos. (Already covered in [[worktree-edit-discipline]].)
- **Read from bare before worktree existed** — Pre-worktree `Read` of `apps/web-platform/package.json` returned a stale shape (no `overrides`, fewer deps) than what `origin/main` HEAD actually had. The bare repo's working-tree-equivalent is whatever was last checked out there — not authoritative. **Prevention:** when a worktree will be created for the task, defer file reads until the worktree exists; never grade a "current state" check against the bare's stale tree.
- **Almost-mis-recovery via "reset to remote"** — First recommended recovery option would have silently re-introduced pre-merge state. **Recovery:** `gh pr list` check before acting. **Prevention:** see Solution above.
