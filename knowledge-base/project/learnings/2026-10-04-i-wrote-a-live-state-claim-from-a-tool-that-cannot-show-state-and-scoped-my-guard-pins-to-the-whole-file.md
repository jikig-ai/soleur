---
title: I wrote a live-state claim from a tool that cannot show state, and scoped my guard pins to the whole file
date: 2026-10-04
category: workflow-issues
tags: [review, guards, observability, runbooks, github-actions, mutation-testing]
related: ["#9391", "#9476", "#9451"]
---

# Learning: a state claim needs a tool that can answer "no", and a guard pin needs the block its property lives in

## Problem

PR-2 of the Zot / ADR-096 wrap-up added a Better Stack alert for `ghcr_blocked=0` and a drift guard for it. Two defect classes
survived a green guard, a 28-row mutation battery and a 13-seat panel, and were found by the fix-round seats.

1. **A live-state claim read from a tool that cannot express the state.** I concluded "the operator re-enabled both apply
   workflows today (`state=active`)" and wrote it into the runbook, ADR-218 and the PR text. `gh workflow view` prints no state
   at all, and `gh workflow list --all` stops at 50 rows, so `apply-web-platform-infra.yml` was simply absent from the list; the
   only workflow I saw was the active one. The workflow had been disabled again at 12:06Z, 12 minutes before the commit. The
   consequence claim ("merging this PR triggers the production push apply") was wrong in the same direction.
2. **Guard pins scoped to the whole file, not the block the property lives in.** The push-trigger pin read the whole `on:`
   block (a `pull_request:` block could satisfy it), the infra-validation pin counted a path line anywhere in the file (the
   `push.paths` list satisfies it), the guard step's `continue-on-error`/`if:` were unpinned, nested decoys (`metadata = { … }`)
   satisfied top-level attribute checks, and the web-sink reachability scan covered the interval AFTER the sink, where an `exit`
   cannot stop it, instead of the interval before it. Each pin was green on the real tree and survivable by a one-line edit.

## Solution

- State claims in docs are a dated observation plus the command that reads the state, never an assertion. The runbook now says
  `gh api repos/<o>/<r>/actions/workflows/<file> --jq .state`, records the observation with a UTC time, and every consequence
  sentence ("a merge triggers the apply") is conditional on that state.
- Every guard pin is extracted to the block it is about (`awk` range on the `push:` sub-block, the `pull_request:` block, the
  job and step, the exploration `query`/`variable` sub-blocks, the cron.d `write_files` entry) and the extraction is asserted
  non-empty by a positive count on the same variable before any `! grep` over it (a negative over an empty extraction is
  vacuously true). One mutation row per scoped pin: move the line into the sibling block, add a negation, add
  `continue-on-error`, put `if: false` on the job.
- A runbook's decode function is executed by the guard against synthetic rows (non-JSON, object message, a forged tail), so
  prose that tells an operator what to run cannot rot while the suite stays green.

## Key Insight

Ask of every claim and every pin: *what does the instrument return when the answer is "no"?* `gh workflow view` returns a
header, a truncated list returns a shorter list, a whole-file grep returns a match from the sibling block, and an `exit` scan
over the wrong interval returns clean. Each answers confidently with something that is not the property.

## Session Errors

1. **Wrote "re-enabled, both `active`" into three docs from a tool that prints no state and a list that drops rows.** Recovery:
   `gh api` read at review time (agent-native and user-impact seats both found it), notes rewritten as dated observations.
   **Prevention:** a state claim in a committed doc is a dated observation with the read command; read state with `gh api
   .../actions/workflows/<file> --jq .state`, never `gh workflow view`/`list` (work key-principles bullet).
2. **Guard pins scoped to the whole file; sink-reachability scan over the wrong interval; M25 pinned a non-property.** Recovery:
   block-scoped extractions plus M18-M29. **Prevention:** per pin, name the block the property lives in and mutate a decoy into
   the sibling block.
3. **MD038 (spaces inside code spans, e.g. `` ` zot_last_err=` ``) hit four times across three files.** Recovery: reword to
   `zot_last_err=` field. **Prevention:** write the delimiter token without padding spaces and describe the position in prose.
4. **Harness slips: an awk anchor that missed a trailing comment on the function line, an extractor that captured the markdown
   fence, `\\n` vs `\n` escaping in a nested mutation program, rows that "did not land" miscounting `MUT_ROWS_RUN`.**
   Recovery: each caught by the next run. **Prevention:** run the extractor on the real file and print what it captured before
   building a fixture on it; count a row that fails to land.
5. **Shell cwd reset to the repo root after a compound command, so a later command ran outside the worktree.** Recovery: chain
   `cd <worktree> &&` in every call. **Prevention:** none beyond that.

## Tags

category: workflow-issues
module: apps/web-platform/infra betterstack-logs-alerts, apps/web-platform/test/infra
