---
title: A new suite is invisible to the repo-global ratchets until it is tracked, and my own review fix moved the event behind a hang
date: 2026-10-04
category: workflow-issues
tags: [ratchets, guard-vacuity-floor, review, mutation-testing, self-heal, nft, observability]
related: ["#9392", "#9451"]
---

# Learning: ratchets read `git ls-files`; the fix for a finding is the next review's surface

## Problem

PR #9451 fixed the `op=enforcement_missing` self-heal read (#9392): `nft ... | grep -q` under `set -euo pipefail`
read SIGPIPE (141) and failed reads as "rule missing". It added a new floor-bearing suite
(`cron-egress-self-heal.test.sh`), changed a loader, a post-apply assertion, a runbook and three ADRs.

Three things went wrong in ways my own gates could not see:

1. **`scripts/guard-vacuity-floor.test.sh` was green when I ran it and red in review.** It enumerates floor-bearing
   suites with `git ls-files`; my new suite was untracked at that moment, so the ledger did not grow 47 -> 48 until
   the file was committed. A repo-global ratchet run before the new file is tracked answers about a tree that does not
   contain it. Same family: `fixture-relative-assert` read 62/0 at one moment and 60/2 once the file was visible.
2. **My first review-driven fix created the next P2.** I moved the Sentry event AFTER the loader re-run (egress is
   open until the loader finishes, so it should not wait behind a 10 s POST). That made the event depend on the
   loader terminating: a wedged loader, which is the #9392 contention hypothesis, is killed with the unit at 120 s
   and takes the event with it. Round 1 found it; the fix is `timeout -k 2 60 "$LOADER"` so rc 124 still reaches
   the event and `fail`.
3. **Two of my mutation rows did not mutate anything, and one mutant ran a real 999 s `sleep`.** A `sed` that
   replaced text with equivalent text, a plain `grep` that does not exit early (so no SIGPIPE), and a clamp row
   whose mutant (clamp removed) turns `NFT_RETRY_SLEEP=999` into a real sleep in a harness that keeps the real
   `sleep` on PATH.

## Solution

- Stage or commit a new test file BEFORE running any repo-global ratchet (`guard-vacuity-floor`,
  `fixture-relative-assert`, `fixture-dir-operand-assert`, `lint-orphan-test-suites`); they read tracked files.
- When a review finding says "X happens too late", check what the fix makes X depend on, then bound that dependency
  (`timeout`) rather than only reordering.
- Bound every value a mutation row can turn into real time (single-digit clamp, 12 s at most) and assert that each
  mutation row's mutant output is non-empty and differs from a pristine control; add a harmless-mutant row that
  must equal pristine.
- ENOENT from `nft list` is a fact about the object (rc 1 and an `Error: No such file or directory` first line),
  not a substring of any failure text: a missing binary (rc 127) ends in the same words.

## Key Insight

A guard's own fixtures are written against the shape of the bug in hand; the review finds the other shapes. Here
that was four times: the call site (never executed by a suite), the payload values (only key names pinned), the
retry bound (never asserted), and the ENOENT anchor (substring). One roll-up covered all of them: the suite pinned
the nodes and not the wires. Executing the extracted block with stubs closed the call-site class in one move.

## Session Errors

1. **A `cd` into a sibling worktree** (to read its status) moved the primary working directory; the next commands
   would have run there. — Recovery: `cd` back and verified branch. — **Prevention:** chain `cd <worktree> && ...`
   in the same call, never a bare `cd` into another worktree.
2. **`Write` refused twice ("modified since read")** — a seat's sandbox or my own edit touched the mtime. —
   Recovery: Read then Write. — **Prevention:** Read the head of a file immediately before a full rewrite.
3. **Scripted multi-edit aborted on a wrong literal** (resolver comment wrapped differently than I remembered), and
   later three mutation literals went stale after the code changed. The anchor assertions aborted before any write,
   as designed. — **Prevention:** after editing code that a mutation row anchors on, grep the suite for the old literal.
4. **First suite run RED from my own bugs** (row() argument offsets, a rc captured inside a subshell). —
   **Prevention:** drive the harness once with a known-good case before adding rows.
5. **`bash t.test.sh 2>&1 | tail` style rc read** — I printed `RC=$?` after a `$(...)` and read 0 while the log held
   2 failures. — Recovery: read the log, not the rc echo. — **Prevention:** `rc=$?` on its own line (already a rule).
6. **A mutation row with a real-time mutant** ran 999 s in the background and held the shell. — Recovery:
   TaskStop, checked for orphans via proc.sh, bounded the value. — **Prevention:** see Solution.
7. **Edited the tree while a full-gate (affected) run was in flight**, twice, so its verdict described no commit;
   the second relaunch then queued 30 min behind a sibling session. — Recovery: killed it, recorded that the gate
   did not run, relied on CI per the operator's standing note. — **Prevention:** freeze the tree during a gate or
   run it from a detached worktree at the SHA being certified.
8. **Stop hook flagged closing sentences naming a next action** ("X follows") as an unkept promise. —
   Recovery: end a blocked turn with a `<stop>BLOCKED: ...</stop>` that names what is awaited. — **Prevention:**
   state the wait, not the intention.
9. **guard-vacuity-floor green locally, red in review** (untracked file). See Problem 1. — **Prevention:** see Solution.
10. **The review fix introduced a new defect** (event behind a hang), and the round-1 panel found it. —
    **Prevention:** for each reordering fix, name what the new order makes the later step depend on.

## Tags
category: workflow-issues
module: apps/web-platform/infra, review
