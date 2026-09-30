---
title: A rate-limited fix agent left three commits the handoff said did not exist
date: 2026-09-30
category: workflow-issues
module: plugins/soleur/skills/review
tags: [review, subagent, rate-limit, scratchpad, handoff, pr-9163]
issue: 6604
pr: 9163
---

# Learning: a rate-limited fix agent left work the handoff said did not exist

## Problem

PR #9163's review fix pass (four rounds: Guard 5 fail-closed, host guards, workflow wiring, docs) was
delegated to one agent. It died on a weekly rate limit (HTTP 429). The context summary written
afterwards recorded "the fix agent made no edits" and told the next session to re-apply the whole
brief. In fact the agent had committed three rounds locally (`fb8ea61d36`, `48f5221aaa`,
`8233d14447`, ~1,450 lines, suites green) and left the docs round uncommitted — none of it pushed, so
the PR head on GitHub still read the pre-review SHA. Separately, the session scratchpad holding the
fix brief and all ten seat reports had been wiped between sessions.

Re-applying the brief from scratch would have duplicated or collided with three reviewed commits.

## Solution

1. Trust the tree, not the handoff: `git log origin/main..HEAD`, `git status --short`, and
   `git rev-parse HEAD` vs `gh pr view --json headRefOid` before re-dispatching anything.
2. Read the commit bodies to map which brief items each round closed; only the docs round
   (runbook/ADR/plan edits, most already in the working tree) remained.
3. Recover the lost brief from the session transcript (`~/.claude/projects/<proj>/<session>.jsonl`,
   the `Write` tool_use whose `file_path` was the brief).
4. Finish the residual items inline, run the touched suites, commit, push, then merge `main`
   (five conflicts from #9123 landing meanwhile, resolved as unions; census floor 93 → 95, measured).

## Key Insight

An agent that fails mid-run is a PARTIAL writer, not a no-op: its failure message describes the
last API call, never the tree. The only reliable record is git. And a scratchpad is not durable
across sessions — a multi-session review's brief belongs under the worktree's gitdir
(`$(git rev-parse --git-dir)`) or in a committed spec file, not in the session scratchpad.

## Session Errors

1. **Fix agent rate-limited mid-run; handoff claimed no edits.** Recovery: `git log`/`status` showed
   three local commits + uncommitted docs. **Prevention:** review skill bullet — after any fix-agent
   failure, reconcile `git log origin/<branch>..HEAD` + `git status` before re-dispatch.
2. **Scratchpad (brief + 10 seat reports) wiped between sessions.** Recovery: brief extracted from the
   transcript jsonl. **Prevention:** same bullet — persist multi-session review briefs under
   `$(git rev-parse --git-dir)`.
3. **`git rev-parse` on the remote-tracking ref failed right after a refspec fetch.** Recovery:
   `gh pr view --json headRefOid` + `git ls-remote`. **Prevention:** read the PR head from `gh`, not a
   tracking ref.
4. **Cutover-workflow suite run from `apps/web-platform/infra` exited 1** ("run from the repo root").
   Recovery: re-ran from the root. **Prevention:** run infra suites from the worktree root.
5. **Merge conflicts with main in five files** (#9123 ADR-119 addendum, C4, `PROMOTED_FILES`, census
   `FLOOR`, generated JSON). Recovery: unions; JSON regenerated via `regenerate-c4-model.sh`; floor
   re-measured. **Prevention:** already covered by review §1's `git merge-tree` pre-panel check —
   re-run it before ship on long-lived branches.
6. **Suite batch overran the 600 s foreground timeout** (the slow `workspaces-boot-unlock` suite).
   Recovery: it continued in the background. **Prevention:** run known-slow suites with
   `run_in_background` from the start.
7. **`grep` "stray \" warning in a push output filter.** One-off; harmless. **Prevention:** filter
   ANSI with `sed 's/\x1b\[[0-9;]*m//g'` rather than a grep escape.
8. **`lint-infra-no-human-steps` rejected the session-state commit** (a "do not reboot" phrasing).
   Recovery: reworded. **Prevention:** the hook is the guard; no action.

## Tags

category: workflow-issues
module: plugins/soleur/skills/review
