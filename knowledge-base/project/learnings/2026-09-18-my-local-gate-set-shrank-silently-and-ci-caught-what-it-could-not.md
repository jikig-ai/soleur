---
title: "My local gate set shrank silently, and CI caught three defects it should have"
date: 2026-09-18
category: workflow-issues
tags: [lefthook, hooks, lints, mutation-testing, signals, systemd, guards]
issue: 6894
pr: 8248
adr: ADR-225
---

# My local gate set shrank silently, and CI caught three defects it should have

## What happened

Three commits on #8248 landed with every local hook skipped. The signal was one line above the
commit output:

```text
Can't find lefthook in PATH
```

`git commit` returned **0**. The commit was created. Nothing else said anything. Two commits later,
running `git push` from a shell whose PATH *did* include the runner, lefthook ran normally — and a
`gitleaks` shim resolution error then failed a commit outright, which is how I noticed the earlier
runs had not been running anything at all.

What the skipped hooks would have caught, and what CI caught instead, one file at a time:

| Defect | Found by | Local hook that was skipped |
| --- | --- | --- |
| The cutover script traced its own LUKS passphrase (`set -x` with a live credential, #7797) | `lint-shell-trace-credential-refusal` in CI | the same lint, wired into the pre-commit set |
| Two `/etc` rewrites allocated a tempfile with no owning trap (ADR-129) — a death between `mktemp` and `mv` leaves `fstab.cutover.XXXXXX` on a host with no inbound channel | `lint-trap-tempfile-ownership` in CI | same |
| `resume_writers` started `inngest-server.service` unconditionally, re-arming a scheduler an operator had quiesced | `ci-deploy.test.sh`'s start-writer inventory, in CI | (repo-global; not in the local set at all) |

## Why it matters

The third row is the documented class — **a file-selected suite set cannot see a repo-global
ratchet** — and I was already applying its remedy, running the suites that reference my changed
files. That is exactly why the first two rows are the interesting ones: those two lints *are* in the
local hook set, they *do* select on the changed files, and they still did not run, because the thing
that runs them was absent from PATH and said so in a line that does not fail anything.

A missing hook runner is not a missing check. It is a **silent downgrade of the entire local gate
set** — every hook at once, with a non-zero-looking message and a zero exit code. The failure mode
of one lint is loud; the failure mode of the runner is a quiet green.

## Prevention

- **Treat `Can't find lefthook in PATH` as a failed commit, not a warning.** If the line appears,
  the commit ran no checks: re-run the hook set by hand, or put the runner on PATH and amend.
- **When a session's commits print that line, run the repo's lints explicitly before pushing** —
  the credential/trace lint, the tempfile-trap lint, the vacuity floor, the fixture-relative ratchet
  and the orphan-suite lint are all cheap and none of them needs the whole battery.
- **Do not conclude from "my suites are green" that the gate set ran.** The suites answer a question
  about the code; the runner answers a question about whether anything asked.

## Two defects the new suite found in the script it was written for

Worth recording separately, because both are about the shape of the test rather than the shape of
the code, and both are reusable:

1. **A signal does not fire the `ERR` trap.** `inngest-luks-cutover.sh` traps `ERR` and resumes every
   writer it stopped — but systemd's `TimeoutStartSec` kill arrives as `SIGTERM`, which walks past
   that trap and leaves the scheduler dark. The suite only saw it because a case models the KILL
   (a stub that hangs, and a `SIGTERM` to the recorded PID) rather than only modelling failures.
   The fix needed a second edit the first one missed: `PHASE=frozen` had to move ABOVE the first
   `systemctl stop`, because a kill landing *during* the stops otherwise resumed nothing at all —
   the handler was correct and the state it read was not yet true.
2. **A variable first dereferenced on the critical path is an unguarded input.** The passphrase was
   read mid-swap, with the store unmounted, where `set -u` would kill the script *without* the trap.
   Asserted present before anything stops. The general form: for each input, ask *where is this
   first read* — if the answer is "after the point of no return", the check belongs before it.

## And one about my own assertions

Two mutation rows survived, both because the assertion I wrote to pin a gate matched a **substring**:

- `grep -qF 'present:luks-cutover'` passed against a mutant that had renamed the case arm to
  `present:luks-cutover-DISABLED)` — the arm was gone and the row was green.
- A fail-closed refusal was pinned by a message prefix two different arms share, so deleting one arm
  left the other satisfying the row.

This is `cq-assert-anchor-not-bare-token`, hit inside the rows written to pin a guard's own
ordering. Anchor case arms as arms (`^[[:space:]]*<arm>\)`), and when two arms share a prefix, pin
each by its own distinct sentence *and* the count.

## Related

- `knowledge-base/project/learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md`
  — the repo-global ratchet blind spot this sits next to.
- ADR-129 (tempfile ownership), #7797 (xtrace credential refusal), ADR-225 (the FSM pattern).
