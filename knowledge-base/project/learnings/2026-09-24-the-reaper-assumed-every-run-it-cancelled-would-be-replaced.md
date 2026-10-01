---
title: "The reaper assumed every run it cancelled would be replaced, and its snapshot rule acted after the snapshot went stale"
date: 2026-09-24
category: workflow-patterns
tags: [ci, github-actions, guards, mutation-testing, review]
issue: 8669
---

## What was built

`.github/workflows/cancel-superseded-pr-runs.yml` plus `.github/scripts/cancel-superseded-pr-runs.sh`
cancel a same-repo PR's workflow runs whose head SHA is no longer the PR head (ADR-216 addendum
2026-09-24). The suite pins the selection rules, the run-mode order and the workflow's whole shape.

## Key insights

- **A population rule is a claim about every member's lifecycle.** "Cancel runs on superseded
  SHAs" is safe only for workflows that re-run on the new head. `board-status-sync.yml` fires on
  `opened`/`ready_for_review`/`closed` only, so reaping its queued run loses the board transition
  for good. The fix keys the population on the fan-out ledger, whose rows mean "fires on
  `synchronize`", and fails closed when the ledger is unreadable.
- **A rule evaluated on a listing snapshot is not enforced at action time.** "Never cancel an
  in-progress `pull_request_target` run" read the status from the listing; the POST happened after
  up to 10 s of head-check sleep. The fix re-reads the run immediately before its POST.
- **A self-run mutation battery measured the axes I was thinking about.** 22/22 killed, then the
  test-design seat found 43 survivors on axes the battery never edited: the workflow wiring (all
  existence greps), the verdict-owning helpers (`expect()`, `no_unexpected()`), and fixtures that
  all pointed one way (single-character SHAs, one shared date, dry runs without skip rows). Round
  two pinned the whole workflow shape and self-tested every verdict helper: 57/57.

## Session Errors

1. Planning subagent hit an API session limit mid-deepen. **Prevention:** resume with SendMessage (kept its transcript); none needed beyond that.
2. Planning subagent's CTO/spec-flow agents never returned to it; findings arrived via the lead. **Prevention:** mark the Domain Review `reviewed (partial)`, as was done.
3. `sleep 30` blocked by a hook in the planning subagent. **Prevention:** wait on notifications, not sleeps.
4. The gh stub flattened its call log to one line, and `last_line_of -- '--paginate'` passed `--` as the pattern — 3 false FAILs. **Prevention:** log one call per line; pass patterns with `--` only to tools that take it.
5. `MIN_ASSERTIONS` guessed (150) before measuring. **Prevention:** set the floor from the first green run, adjacent to its `if`.
6. shellcheck SC2015/SC2016/SC2034 on the new suite. **Prevention:** run shellcheck before the first commit of a new `.sh`.
7. Missing xtrace refusal flagged by `lint-shell-trace-credential-refusal.py`. **Prevention:** start any script that runs with a token from the `case "$-"` refusal block.
8. `awk -v re='…\|$'` processes escapes in `-v`, so the regex became an alternation and the extraction was empty. **Prevention:** write a literal `|` as `[|]` in any regex passed through `awk -v`.
9. `grep -v '^ *#' fileA fileB` prefixes each line with the filename, so the comment anchor never matches (a latent vacuity in the first W4 check). **Prevention:** use `grep -h` whenever an anchored pattern runs over more than one file.
10. Population assumption (board-status-sync). **Prevention:** routed to `plan/references/plan-sharp-edges.md`.
11. Snapshot rule acted on later (rule 9b). **Prevention:** re-read any state a destructive action depends on immediately before the action.
12. Self-run battery covered 0 wiring rows and 0 verdict helpers. **Prevention:** list the battery's axes (SUT / wiring / helpers / fixture direction) before calling it complete.
13. My ship note said to merge from a detached worktree, but `cd <dir> && gh pr merge …` in one call is judged against the old cwd (the hook reads the tool call's `.cwd`). **Prevention:** read the hook's input source before documenting how to bypass it; the note now says the `cd` must be a separate, earlier call.
14. Consumer-suite batch exceeded the 600 s foreground limit. **Prevention:** run multi-suite batches in the background with a Monitor on the result file.
