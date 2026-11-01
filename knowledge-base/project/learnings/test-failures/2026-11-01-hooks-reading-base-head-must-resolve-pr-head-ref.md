---
title: "hooks reading BASE..HEAD must resolve the PR head ref — the session can root outside the feature worktree"
date: 2026-11-01
category: test-failures
tags: [hooks, ship-gate, git-range, stale-cwd]
---

# Learning

## Problem

`ship-cmo-content-gate.sh` scoped `Reviewed-By-CMO` trailer detection and the
marketing-diff check to `${BASE_REF}..HEAD` / `...HEAD`. The harness passes the
*cwd of the tool call*, and a session rooted at the main checkout has
HEAD==main: the range is empty, no trailer is found, and the gate denies a
compliant PR. Same class hit twice (the issue was filed from a denied run on
#11652).

## Solution

Resolve the PR's own tip, in this order, never trusting HEAD for
branch-scoped reads in hooks:

```bash
PR_HEAD=$(gh pr view "$PR_NUM" --json headRefName --jq .headRefName)
# TIP: origin/<headRef> -> refs/pull/<N>/head -> fetch pull/N/head -> HEAD
```

- `origin/<headRef>` covers the live open-PR case.
- `refs/pull/<N>/head` survives a deleted head branch but only if already fetched.
- `git fetch --quiet origin "pull/<N>/head"` -> `FETCH_HEAD` covers deleted/pruned
  branches lazily — GitHub keeps the pull ref server-side forever.
- HEAD last preserves pre-fix behavior when nothing resolves.

## Key Insight

Any hook that diffs or logs "the PR's commits" is wrong the moment the tool
call's cwd isn't the feature worktree — which is always legal. Resolve the ref;
don't infer it from cwd.

## Evidence

- one-shot #11682 (PR #11794); suite rows 6-8 pin all three TIP arms plus the
  deny counter-case; live e2e on #11652 from the main checkout (deny -> pass).
