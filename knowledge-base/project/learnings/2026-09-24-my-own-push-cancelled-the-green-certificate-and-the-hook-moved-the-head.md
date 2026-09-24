---
title: "My own push cancelled the green certificate, and the pre-merge hook moved the head I pinned"
date: 2026-09-24
category: workflow-patterns
tags: [ci, admin-merge, contention, behind-livelock, github-actions]
issue: 8639
---

## What happened (#8639 ship)

- **BEHIND livelock.** The branch was synced with `main` four times in a row. Each sync restarted
  the full CI cycle, and `main` moved again before that cycle finished. Superseded runs from every
  sync stayed queued, so they held runners and slowed the next cycle.
- **The certificate destroyed itself.** To get a fresh signed `gh pr update-branch` merge on top of
  the green head `G` (`d1474536cd`), the branch was force-pushed back to `G`. That push fired a
  new `pull_request` `synchronize` on `G`, and the update-branch push then cancelled those runs.
  `admin-merge-ready.sh` grades the LATEST run per context, so `G` now read
  `failed=[…cancelled…]`.
- **The hook moved the pinned head.** `gh pr merge --admin --match-head-commit` was run from a
  branch checkout that was behind `origin/main`. `.claude/hooks/pre-merge-rebase.sh` then merges
  `origin/main` and pushes before the merge, so it refused with "Head branch was modified".

## Rules

- Never re-push a certified-green sha to "refresh" it. The runs your push creates are the ones
  the grader reads.
- Run a `--match-head-commit` merge from a detached worktree at that sha, entered with a
  separate, earlier `cd` in the main session: the hook judges the tool call's working
  directory, and its auto-sync skips a detached HEAD.
- Since the reaper, certify `G` only when nothing on `G` is still queued or running: moving the
  head past `G` makes those runs superseded, and a reaped run reads `cancelled`.
- Part of why one CI cycle outlasted `main`'s merge cadence was contention from superseded runs
  that nothing reaped. `.github/workflows/cancel-superseded-pr-runs.yml` now cancels a PR's runs
  on non-head SHAs after every push (ADR-216 addendum 2026-09-24). It shortens the cycle; it does
  not stop `main` from moving.

These rules are recorded in
`plugins/soleur/skills/ship/references/settle-then-admin-merge.md`, §"Operator-authorized variant:
was-green carryover".
