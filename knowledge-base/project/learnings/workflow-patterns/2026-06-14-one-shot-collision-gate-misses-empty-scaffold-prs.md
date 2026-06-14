---
title: one-shot collision gate misses empty-scaffold PRs/worktrees from abandoned sibling runs
date: 2026-06-14
category: workflow-patterns
issue: 5230
tags: [one-shot, collision-gate, worktree, draft-pr, deferred-scope-out]
---

# Learning: one-shot collision gate misses empty-scaffold PRs/worktrees

## Problem

`/soleur:one-shot #5230` ran its Step 0a.5 open-issue collision check and found
**no collision**:

- `gh issue view 5230` → `{state: OPEN, closed_by: []}`
- `gh pr list --search "linked:issue #5230" --state all` → empty

So the gate passed and the run created a fresh worktree
`feat-one-shot-5230-github-retry-cron-octokit`. But an **abandoned sibling
one-shot run** had already left, for the *same issue*:

- a worktree `feat-one-shot-github-retry-probe-octokit-5230` (init commit only,
  empty diff vs main), and
- an **open draft PR #5258** titled `WIP: feat-one-shot-github-retry-probe-octokit-5230`.

The collision gate missed both because:

1. The scaffold draft PR carries **no linked-issue reference** yet (no `Closes
   #5230` / `Fixes #5230` in the body — it is just a `chore: initialize` commit),
   so GitHub's `linked:issue #5230` search returns nothing.
2. The gate never probes for **existing branches/worktrees whose name embeds the
   issue number**, nor for **draft PR titles containing the issue number**.

This is the inverse blind spot of
[[2026-05-29-one-shot-collision-gate-must-probe-merged-prs]] (which hardened the
gate to probe MERGED linked PRs): here the colliding artifact is an *empty,
never-linked* scaffold, not a merged implementation.

Second, smaller friction: the freshly-created worktree **vanished** between
`worktree-manager.sh create` (reported "✓ created successfully", deps installed)
and the next `git worktree list` — absent from the list AND from disk. Likely a
concurrent sibling `cleanup-merged` reap racing the lease write, but the
mechanism was not pinned down this session.

## Solution

Adopt the pre-existing empty worktree instead of fighting the duplicate:

1. Confirmed the existing branch was empty and current: `git rev-list --count
   <branch>..origin/main` = 0 (after a fresh `git fetch origin main` — the local
   `origin/main` ref lagged and first read 0 spuriously), and `git log
   origin/main..<branch>` = just the init commit.
2. Confirmed no active lease: no `.soleur-lease` file, dir stale >24h.
3. Acquired a lease (`source .claude/hooks/lib/session-state.sh; acquire_lease
   <branch> one-shot 240`) and `cd` into it.
4. Ran the whole plan→work→review pipeline into that worktree, landing on the
   existing draft PR #5258 — so the run produced **zero duplicate PRs**.

## Key Insight

The one-shot collision gate keys exclusively on GitHub's issue/PR *link graph*.
An abandoned sibling run leaves on-disk and draft-PR artifacts that are NOT in
that graph (empty branch, unlinked WIP draft PR). Before creating a new worktree,
the gate should ALSO probe local/remote state by **issue-number substring**:

- `git worktree list` / `git branch --list '*<N>*'` for an existing branch, and
- `gh pr list --search "<N> in:title" --state open` for an unlinked scaffold PR.

On a hit with an **empty** diff, adopt-and-reuse (lease + cd + build into it) is
strictly better than creating a competitor — it reuses the existing draft PR and
nets zero duplicates. On a hit with a **non-empty** diff, it is the parallel-
session collision the existing gate already handles.

## Session Errors

1. **Worktree vanished after successful create** — `worktree-manager.sh --yes
   create` reported success + installed deps, but the worktree was gone from
   `git worktree list` and disk seconds later.
   Recovery: adopted the pre-existing same-issue worktree.
   Prevention: after Step 0b create, assert the printed path exists (`test -d
   "$WT" || re-create/adopt`) before `cd`; investigate whether a sibling
   `cleanup-merged` can reap a freshly-leased worktree before its lease lands.
2. **Collision gate missed an existing empty scaffold PR/worktree for the same
   issue** — `gh pr list --search "linked:issue #N"` returns empty for an
   unlinked WIP draft PR.
   Recovery: discovered the existing worktree manually via `git worktree list`;
   adopted it.
   Prevention: extend Step 0a.5 to probe `git worktree list` + `git branch
   --list '*<N>*'` + `gh pr list --search "<N> in:title"` and adopt-or-warn on a
   hit. See route-to-definition issue filed from this session.
3. **AC grep count inflated by prose comments** — inline comments containing the
   literal `octokit.request` broke the AC1/AC2 `git grep -c 'octokit.request'`
   equality with the wrapper count.
   Recovery: reworded comments to avoid the literal (self-caught at verify).
   Prevention: when an AC verifies by `grep -c '<literal>'`, keep that literal
   out of explanatory comments in the same file.
4. **Overstated re-POST safety comment** — a comment claimed the individual-
   wrapper pattern means "a retry cannot double-comment"; it only prevents a
   *sibling* call's retry from re-POSTing, not same-call duplication on a
   response-phase transient.
   Recovery: data-integrity-guardian flagged it; corrected inline.
   Prevention: scope idempotency-safety claims to cross-call, never absolute.

## Tags
category: workflow-patterns
module: one-shot
