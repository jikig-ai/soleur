---
title: "git rebase --continue after a conflicted commit opens an interactive editor that hangs headless shells; killed attempts leave orphan commits holding the index lock"
date: 2026-10-25
category: workflow-patterns
tags: [git, rebase, lefthook, hooks, worktree, pipeline]
---

Measured during PR #11108 (arc-spokes). Rebase of 12 commits onto `origin/main`
conflicted once on `seo-bulk-redirects.tf` (sibling PR #11091 landed a pair on
the same map-tail lines — the pre-planned overlap materialized exactly as
predicted). Three separate stall modes, each read as "hooks running":

1. **`git rebase --continue` on a conflict-resolution commit runs `git commit
   -e` — the `-e` opens `$EDITOR`.** In a headless shell that is `nvim` waiting
   on a TTY that will never come; the process sits indefinitely while every
   probe (`msgnum`, staged diff) looks like a slow hook. The fix is
   `GIT_EDITOR=true git rebase --continue` — resolution message is kept, no
   edit round-trip.

2. **`kill`-ing the outer `git rebase` leaves the child `git commit` (and its
   lefthook→test-all battery) running.** The orphan holds the index lock and
   keeps competing for the `test-all` queue lock; the *next* `rebase
   --continue` then waits on the lock the orphan still holds — two sessions'
   worth of batteries at once. Enumerate `pgrep -a git` and kill the orphaned
   `git commit` too, not just the rebase parent.

3. **`LEFTHOOK_EXCLUDE=bun-test` did not suppress the per-commit battery in
   this repo; `LEFTHOOK=0` did.** The hook that fires `--affected` isn't keyed
   by that name, so each of 12 replayed commits queued a full gate (~17 min
   observed before abort). Commits replayed by rebase already passed hooks on
   first commit — `LEFTHOOK=0` (full bypass, documented escape hatch) is the
   correct knob for replay, not a narrower exclude whose key you haven't
   verified against `lefthook.yml`.

Companion: rerere recorded the conflict *preimage* on both attempts but only
records the *resolution* when the conflicted commit actually completes — two
aborted attempts meant resolving the same hunk three times. Complete the
resolution commit once before interrupting anything.

Regen-class companion finding (review P2): a generated artifact rebuilt
*before* a rebase silently omits everything that arrives via the rebase
(`campaign-calendar.md` missed the #11091 draft until regenerated post-rebase).
Rebuild generated indexes/calendars after the last content-landing rebase,
not before.
