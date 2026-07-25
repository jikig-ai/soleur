---
title: A parallel session can reset the shared PR branch to a different lineage mid-work — detect it before pushing, recover without clobbering
date: 2026-07-24
category: workflow-issues
module: git, worktrees
tags: [git, worktree, force-push, force-with-lease, branch-divergence, parallel-session, pr]
issues: [6459, 6919]
severity: high
---

## Problem

Mid-session, a `git push` to `feat-web-active-active-iac` was rejected ("tip is behind its remote
counterpart") even though my local worktree held three phases of committed, verified work. A parallel
process had **force-reset the shared PR branch to an entirely different lineage** — a Phase-0-only
version on a different base — while my worktree kept building on the pre-reset lineage. The two shared
only a common ancestor; the remote's tip contained NONE of my Phase 1–4 work, and PR #6919's head
pointed at the remote's Phase-0 lineage.

## Root cause

Multiple sessions/worktrees operating on the SAME branch name is this repo's documented workflow, and
nothing prevents one from force-pushing the shared branch out from under another. My worktree's
`origin/<branch>` remote-tracking ref was stale (captured at session start); the branch had moved.

## Solution (the recovery sequence)

1. **Do NOT force-push on a rejected push.** A rejected push over a divergent branch is a signal, not
   an obstacle — force-pushing would destroy the parallel lineage.
2. **Characterize the divergence before acting.** `git fetch origin <branch>`; then compare lineages:
   - `git log --oneline HEAD..origin/<branch>` and `origin/<branch>..HEAD` (each side's unique commits)
   - `git merge-base HEAD origin/<branch>` (do they even share history?)
   - `gh pr view <PR#> --json headRefOid` (which lineage is the PR authoritative on?)
   - `git cat-file -e origin/<branch>:<a-file-only-my-work-has>` (quantify what the remote is missing)
   - commit timestamps (which lineage is newer/more complete)
3. **Back up your lineage to a DISTINCT remote ref immediately** — `git push origin
   HEAD:refs/heads/<branch>-backup`. This makes your work durable without touching the contested branch.
4. **This is an operator decision** (only they know if a parallel session is still live). Surface the
   options: force-update the PR to your lineage (discards the parallel work — safe only if nothing else
   is running on it), rebase your work onto the parallel lineage, or hold and coordinate.
5. **Once decided, use `git push --force-with-lease=<branch>:<expected-remote-sha>`**, not a bare
   `--force`. The lease aborts atomically if the parallel process pushed AGAIN since your fetch, so you
   never silently clobber newer work. `git ls-remote origin <branch>` first to confirm the expected SHA.

## Key insight

**A rejected push on a shared PR branch is evidence of a parallel writer, and the safe primitives are
`--force-with-lease` (never bare `--force`) + a distinct backup ref + an operator decision — never a
unilateral force-push.** In a repo where multiple worktrees share branch names, treat
`origin/<branch>` as untrusted the moment a push is rejected: re-fetch and re-characterize the lineage
(merge-base, per-side commit lists, the PR's own head, timestamps) before choosing an action. Your
work is safe the instant it is committed AND backed up to a ref no other session writes; only then is a
force-update over the contested branch a reversible, non-destructive operation.

## Session Errors

- **Push rejected; branch reset by a parallel process** — Recovery: back up to a distinct ref,
  characterize the divergence, get the operator's call, force-with-lease. Prevention: this learning.
- **ADR-141 number collision** — main landed its own ADR-141 (encryption-posture) while this branch
  used 141 for active-active; renumbered to 142 and swept ONLY this feature's files (the bare token
  `ADR-141` is ambiguous — scope the sweep by classifying each hit as mine vs main's, and verify main's
  references survived untouched). Prevention: the plan already flags "re-verify next-free ADR at ship";
  a merge that surfaces two `ADR-<N>-*.md` files with the same number is the trigger to renumber the
  unmerged one.

## Related

- `plugins/soleur/skills/git-worktree` (shared-branch worktree workflow).
- [[2026-06-30-migration-number-collision-mid-pipeline]] — sibling class (a shared numeric namespace
  two branches both grab; renumber the unmerged one, sweep every in-repo reference).
