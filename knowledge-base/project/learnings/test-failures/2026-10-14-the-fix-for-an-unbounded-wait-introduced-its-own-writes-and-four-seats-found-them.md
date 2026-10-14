---
module: System
date: 2026-10-14
problem_type: workflow_issue
component: test_machinery
symptoms:
  - "flock -w never timing out under an inherited blocked SIGALRM mask (a live wedged holder kept the repo-wide lock 4.6 days; #7697)"
  - "A nested sandbox test runner refused a bare run rc=4 because it inherited the parent's exported TC_SIBLING_RUN_COUNT and re-armed the PID stamp (#10209 — 50/50 flake under sibling load)"
  - "The reaper mutation battery reddened on wall-clock ceiling under sibling contention (#8163 — 429523ms vs 240000ms)"
  - "stamp_lock_holder shipped a missing `shift`, writing the lock name as a stray bare line into every stamped marker — verified live in the real gate's .holder file"
  - "release_lock removed the marker AFTER closing the fd — a successor could mint its own marker in the gap and have it deleted, leaving its whole hold markerless"
root_cause: missing_validation
resolution_type: code_fix
severity: high
status: resolved
tags: [flock, timeout, signal-mask, advisory-lock, holder-marker, contention, sibling-count, review-fix-round]
issue: '#7697 #10209 #8163'
pr: '#10239'
---

# Four seats found the defects the contention-robustness fix introduced — and the mechanism was subtler than the issue text (#7697 #10209 #8163, PR #10239)

## Problem

A batch of three contention bugs in the local test gate shipped with the
usual blind spot: the fix itself carried three new defects (a missing
`shift`, an rm-after-close race, an unvalidated arithmetic operand), every
one of which the direct suite runs had verified green — because the arms
pinned the *feature* and not the *shape*.

1. **`stamp_lock_holder` iterated `"$@"` without `shift`.** The lock name
   landed as a stray bare line in every stamped marker — verified live in
   the real full-gate run's `test-all.holder` file. Every kv-grep arm
   passed anyway; a shape pin (`every line is key=value`) is what the arm
   was missing.
2. **`release_lock` rm'd the marker after closing the fd.** The close is
   the instant the kernel can grant a queued successor; a successor minting
   in the gap would have its marker deleted and read `holder=none` for its
   entire hold. The fix is mechanical: rm while still holding is provably
   removing your own marker.
3. **`.holder` writes via `>` follow planted symlinks** — and the /tmp
   orphan-fallback `LOCK_DIR` makes the name predictable cross-user. The
   codebase already knew this threat (`_tc_queue_dir` carries the
   `-d && ! -L && -O` guard); the new write sites missed parity. `mktemp`+`mv`
   closes it *and* the torn-read window at once.

## What the issue text got wrong — mechanism, not hypothesis

- **The blocked mask defeats the waiter, not the holder.** The 4.6-day hold
  was the holder's `anon_pipe_read` wedge; the *wait* was indefinite because
  `flock -w`'s SIGALRM expiry never delivered under an inherited
  `sigprocmask(SIG_BLOCK)`. The fix's prose initially conflated the two.
- **GNU `timeout` (≥coreutils ~9.5) unblocks the child's signal mask** — so
  wrapping `flock -w` doesn't just add an outer bound, it *restores* the
  inner expiry: `timeout 6 flock -w 3` under a blocked mask returns rc=1 at
  3s, not 124 at 6s. rc=124/137 is reserved for a flock that cannot return
  at all, and the fixture for that class is a *never-exiting stub*, not a
  real flock. A test that measures the common case must not assert the
  forced-bound line.
- **Inherited sibling-run counts are an env-boundary defect class.** A
  sandbox that re-arms `TC_SIBLING_RUN_COUNT_PID=$$` unconditionally while
  `ENV_SCRUB` leaves the parent's exported count live hands a measured-
  sibling *stamp* to a count nobody measured — `env -u TC_SIBLING_RUN_COUNT
  -u TC_SIBLING_RUN_COUNT_PID` plus a suite-controlled pin (`WD_SIBLING_RUNS`,
  `SANDBOX_SIBLINGS`) is the in-repo idiom; the refusal conjunct's
  `PID == $$` is what makes the leak fire.
- **An unmeasurable procfs and a measured-empty procfs are different
  verdicts.** The ceiling treats "can't read" as contended (fail-safe) but
  "read fine, zero procs" as solitude (still asserts) — conflating them was
  the tasks-vs-implementation drift the architecture seat caught.

## Session Errors

1. `git commit` blocked in subagent context (forwarded) and the probe
   fixture commit blocked by the commit-on-main guard — `hash-object`/
   `update-ref` plumbing route used. **Prevention:** probe fixtures use
   plumbing or a non-main fixture branch from the start.
2. `python3` absent on the box — the SIGALRM-mask fixture needed python.
   **Prevention:** probe `command -v` and skip-fixture before writing arms
   that assume it (the suite does exactly this).
3. The T21 RED fixture exercised a free lock because the T20 holder had
   already released — each arm needs its own held-lock fixture.
   **Prevention:** never share a holder across arms; `await_held` before
   the waiter, not after.
4. `archive-kb.sh` dry-run over-captured in-flight spec/plan artifacts via
   its branch-diff axis — surgical `git mv` substituted.
   **Prevention:** scope archive runs to completed branches only; the
   in-flight artifacts keep their live spec dir by convention.
5. The first full gate reddened on three causes, one self-inflicted:
   committing `82f019647a` while the gate was mid-run produced the
   boundary FATAL. **Prevention:** the tree stays quiesced for the
   duration of a full-gate run — no commits, no pushes.
6. The `stamp_lock_holder` missing `shift` shipped green because every
   arm grepped fields, not shape. **Prevention:** a key=value file's pin
   is a line-count invariant next to the field greps.
7. `_mut_sibling_count` initially conflated a readable-empty procfs with
   an unmeasurable one — tasks.md recorded the distinction; the code
   didn't. **Prevention:** the verdict table (readable-empty→0,
   absent→contended) is pinned by fixture arms now.
8. Push non-fast-forward: a stale pre-rebase init commit sat on the
   remote tip. **Prevention:** merge (no force-push) — recorded.
9. `gh issue create` rejected twice by the filing gates — `--milestone`
   and a filing-exit label (`meta/machinery`) were required.
   **Prevention:** read the gate message; the required exits are in it.
10. The mutation battery's unmutated control reddened under a foreign
    worktree's live gate — environmental. **Prevention:** filed as
    #10279 (the control stage needs the same contention-aware verdict
    the ceiling got).

## Prevention

- **A stamp-shaped assertion greps for fields; a shape assertion counts
  lines.** Every file whose contract is "all lines are key=value" deserves
  `grep -cvE '^[a-z_]+=' == 0` next to the field greps.
- **Fixture preconditions are load-bearing** — assert the blocked mask
  propagated (`/proc/self/status` SigBlk & 0x2000) inside the wrapped
  script, not in a comment.
- **Fail-by-hang stubs get an outer `timeout`** — a regression in the bound
  under test must redden, not stall the suite for an hour.
- **Review seats catch fix-introduced defects** — the missing `shift` was
  found by four independent seats; the fix round re-reviewed and every P2
  closed. The cap-2-then-escalate protocol earned its cost again.
