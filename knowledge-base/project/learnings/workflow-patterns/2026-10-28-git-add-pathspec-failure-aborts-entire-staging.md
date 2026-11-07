---
date: 2026-10-28
category: workflow-patterns
title: "One bad pathspec aborts the whole `git add` — a commit can ship a rename without its payload"
---

## Session Error

During the #11445 fix round, `git add <file1> <file2> scripts/probes <file3>` failed with
`fatal: pathspec 'scripts/probes' did not match any files`. The path no longer existed
(`git mv` had emptied it), and — load-bearing — **git aborts the entire add on one bad
pathspec**: none of the listed files staged. A subsequent `git commit` recorded only what
`git mv` had already staged (a rename of the pre-fix blob), while every hardening edit sat
uncommitted in the worktree. Two review seats caught it by diffing the commit rather than
trusting the commit message ("addresses findings X, Y, Z" — which were all still WT-only).

## The Rule

After any `git add` with multiple pathspecs, verify `git diff --cached --stat` is non-empty
and covers the intended set BEFORE committing — a `fatal: pathspec` line mid-output means
zero files staged, not partial staging. And `git mv` stages the rename immediately, so a
commit made after a failed `git add` silently ships "move only" while the working tree
carries the real payload.

## Detection

Cheap, mechanical, pre-commit: `git diff --cached --stat` + `git status --short` — any ` M`
next to files you meant to commit is the tell. Fix-round seats diffing `PANEL_SHA..HEAD`
independently re-found it within minutes — the seat-vs-commit-message check is what makes
this recoverable rather than silent.
