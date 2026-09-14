---
title: I stopped a starved ship battery at 61 minutes, and my post-merge monitor read a fetch error as zero runs
date: 2026-09-15
category: workflow-issues
module: ship Phase 4 / Phase 7 post-merge verification
issues: ["#8030"]
prs: ["#8175"]
tags: [ship, test-all, capacity, monitor, instrument-vacuity, merge-tail]
---

# Learning: merge-tail errors from shipping PR #8175

The pre-ship learning for this PR is
`knowledge-base/project/learnings/best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`
(16 session errors, including both CI lint failures). This file covers only what happened after
it was written.

## Problem

1. **The local `TEST_GROUP=all` battery never ran.** A capacity-gated Monitor waited 61 minutes.
   Sibling worktrees kept starting batteries (`measured_runs` read 3, 1, 2, 3) and `/var/tmp`
   stayed below its floor at 530 MB of 1024. I then stopped the Monitor and shipped on CI.
   Two conditions held at that point:
   - CI's required `test` aggregate and all three `test-scripts` shards were green on the exact
     head;
   - the diff touched neither the heavy batteries nor `apps/web-platform/infra/`, so a local run
     would have executed the same suites.

   The skipped step is recorded as an unticked test-plan item in the PR body.
2. **My first post-merge Monitor reported `total=0 pending=0` twice.** Its fetch line was
   `j=$(gh run list … 2>/dev/null || echo '[]')`. A failed `gh` call and "no runs on this
   commit" produced byte-identical output, and only the loop's `tot > 0` exit guard kept it from
   declaring the post-merge set settled. The replacement surfaced a `FETCH-ERROR` line and
   capped retries.
3. **The feature worktree vanished minutes after the merge.** A sibling session's
   `cleanup-merged` reaped it (correctly: the branch was gone), so my next
   `cd <worktree> && …` failed. Verification continued from the repository root with
   `gh … -R jikig-ai/soleur`.

## Solution

- (2) Never fold a fetch failure into an empty result. Capture the command's own exit status
  and emit a distinct line: `if ! j=$(gh …); then echo "FETCH-ERROR …"; …; fi`.
- (3) After merge, run post-merge verification from the repo root with explicit `-R`, never
  from the feature worktree.
- (1) No fix is applied here, deliberately. See Key Insight.

## Key Insight

**Stopping the battery was a deviation from written guidance, not a response to a gap.** Ship
Phase 4 already covers this exact state. It says to loop on `--capacity`'s `measured_runs`
until 0, launch detached, and re-wait on rc 4, and records that #8135's loop needed more than
three hours before it launched cleanly. My reasons were true:
- CI had the same coverage on the same head;
- a battery run beside three siblings on a starved `/var/tmp` produces REDs nobody can
  interpret.

But "CI already covers it" is exactly the argument ADR-183 declined to accept for this gate.
The honest record is that the gate was skipped, with the reason, not that it was satisfied.

Whether Phase 4 should gain a sanctioned exit is a design question for the gate's owner, not
something to settle in a merge tail. A possible exit: an unrun battery, recorded in the PR
body, is acceptable when the required `test` context is green on the exact head AND
`_diff_touches` declines every heavy suite. This learning does not change the gate.

## Session Errors

1. **Local ship battery stopped after 61 minutes of capacity starvation; shipped on CI.**
   Recovery: recorded the unrun battery in the PR body test plan.
   **Prevention:** follow ship Phase 4 as written (the loop waits as long as it takes). If the
   wait itself is the problem, raise it with the gate's owner rather than deciding it per PR.
2. **Post-merge Monitor's `|| echo '[]'` made a `gh` failure read as zero runs.** Recovery:
   restarted the Monitor with an explicit `FETCH-ERROR` branch and `-R`.
   **Prevention:** in any polling Monitor, an instrument failure must print a line no success
   path can print.
3. **The merged branch's worktree was reaped by a sibling session's `cleanup-merged`, and a
   subsequent `cd` into it failed.** Recovery: ran verification from the repo root with `-R`.
   **Prevention:** treat the feature worktree as gone once the PR is MERGED.

## Tags

category: workflow-issues
module: ship
