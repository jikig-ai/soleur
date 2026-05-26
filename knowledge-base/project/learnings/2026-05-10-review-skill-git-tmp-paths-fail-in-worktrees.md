---
title: review skill's `.git/review-*.txt` tmp paths fail in worktrees
date: 2026-05-10
category: integration-issues
module: plugins/soleur/skills/review
tags: [review, worktree, gitdir, tmp-paths, classification-gate]
related_pr: 3512
related_issue: 3509
---

# Learning: review skill prescribed `.git/review-*.txt` tmp paths fail in worktrees

## Problem

The review skill's "Change Classification Gate" (Section 1) prescribed three
tmp file writes inside `.git/`:

```bash
git diff --name-only origin/main...HEAD > .git/review-changed.txt
git diff --name-status origin/main...HEAD > .git/review-status.txt
git diff --numstat origin/main...HEAD > .git/review-numstat.txt
```

Running this from a worktree (`.worktrees/<name>`) failed with:

```
/bin/bash: line 14: .git/review-changed.txt: Not a directory
cat: .git/review-changed.txt: Not a directory (os error 20)
```

The cause: in a worktree, `.git` is a **file** (a gitdir pointer like
`gitdir: /path/to/bare/worktrees/<name>`), not a directory. The redirect
target requires the parent to exist as a directory, and `.git` is not one.
The fix-inline workaround during the session was to compute the actual
gitdir via `git rev-parse --git-dir` and write to `/tmp/...` instead.

The pre-existing literal worked in non-worktree checkouts (where `.git/`
is a directory). It silently broke in worktrees — and the project now
defaults to running reviews from worktrees per
`wg-at-session-start-run-bash-plugins-soleur`.

## Solution

Patched the review skill (`plugins/soleur/skills/review/SKILL.md`) to use
`git rev-parse --git-dir` for the tmp path. The resolver returns the
correct gitdir in both regular checkouts (`./.git`) and worktrees
(`<bare>/worktrees/<name>/`):

```bash
REVIEW_TMP="$(git rev-parse --git-dir)"
git diff --name-only origin/main...HEAD > "$REVIEW_TMP/review-changed.txt"
git diff --name-status origin/main...HEAD > "$REVIEW_TMP/review-status.txt"
git diff --numstat origin/main...HEAD > "$REVIEW_TMP/review-numstat.txt"
```

All downstream predicate computations (`wc -l < ...`, `grep -E ...`,
`awk ...`) updated to use `"$REVIEW_TMP/review-*.txt"`.

## Key Insight

Skills that prescribe `.git/<file>` paths assume a non-bare, non-worktree
checkout. The convention in this repo (bare root + per-feature worktrees)
makes that assumption silently wrong on every review session. The fix is
mechanical: every skill that wants a "scratch space adjacent to the repo
state" should resolve via `git rev-parse --git-dir`, not hard-code `.git/`.

This is a sibling pattern to AGENTS.md's
`hr-when-in-a-worktree-never-read-from-bare`: the rule warns about
**reads** from bare, this learning addresses **writes** to a path that
doesn't exist as a directory.

## Session Errors

- **`.git/review-changed.txt: Not a directory` (and 2 sibling files)** —
  Recovery: switched to `/tmp/review-3509/` after resolving actual gitdir
  via `git rev-parse --git-dir`. Prevention: patched the review skill to
  use `REVIEW_TMP="$(git rev-parse --git-dir)"` (this PR commit).

## Tags

category: integration-issues
module: plugins/soleur/skills/review
