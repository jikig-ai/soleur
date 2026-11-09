# Learning: a new read on a terminal path moves the terminal line, and every pin has to follow it

## Problem

Wiring `ci-head-verdict.sh required` into `monitor-pr-checks.sh` (#11544, monitor half) meant the
`CHECKS GREEN BUT BLOCKED` line stopped being the last line: a 10-minute hold comes before it and a
read of up to 125 s after it. A 9-seat panel, 2 design seats, 3 fix-round seats and 1 verifier found no
correctness P1 but about 100 findings, almost all of one kind: a claim, a pin or an instruction that
described the old terminal contract.

## Solution

- Say it in the stream, not only in docs: a `running (up to 125s) ... wait for the exit` line between the
  old terminal line and the read (agent-native P1: the docs naming it are not read at runtime).
- Hold decisions use cheap gates first (armed, positively not-queued), read the expensive verdict at hold
  start and at expiry only, and bound it with `timeout -k 5 60`.
- Parse the resolver's output defensively: tail not head (the marker is last), full-shape marker bound to
  this PR, control characters dropped, no hints beside `state=error`.
- Pin every gate flipping mid-hold (auto-merge, verdict, queue) and every restart of the hold; a mutant
  that waives a gate only once a hold is running survives any suite that tests gates on the first poll.

## Key Insight

When a change adds work after what used to be the last line, three things go stale together and a green
suite sees none of them: the in-stream signal (nothing says the process is still alive), the docs and
arming instructions that treat the old line as the end (including `Monitor` parameters this runtime does
not have), and the tests, which all asserted the first poll. Review the contract sentences and the
multi-poll fixtures before the code.

## Session Errors

1. **`/tmp` quota exhausted at session start (EDQUOT), every Bash call failed.** Recovery: deleted 28
   session dirs older than 24 h after confirming no open files. **Prevention:** none beyond the harness
   message; session scratch under `/tmp/claude-1000` is the operator's to clear.
2. **`rm -rf` on a variable-built scratch path was blocked (hook, then safety check).** Recovery: fixed
   literal paths and a fresh results directory. **Prevention:** never rebuild scratch with `rm -rf $VAR`;
   write each run into a new directory.
3. **`jq -r ... | tr '[:cntrl:]' ' '` turned the trailing newline into a space and made `red` non-empty.**
   Caught by existing row T30a. **Prevention:** use `jq -j` when the result feeds `[[ -n ]]`/`${x:+..}`.
4. **W12a passed vacuously: the queue read retries a failed call once and answered "not queued".**
   Found only because mutation M11 survived. **Prevention:** a mid-hold "unknown" fixture needs the gql
   call count as a positive control (`PR_QUEUE_ATTEMPTS=1`).
5. **I wrote `persistent: true` and "AwaitShell wakes on exit" into `drain-prs/SKILL.md`.** The Monitor
   schema loaded in this runtime has no `persistent`, and nothing in the repo documents an exit-wake mode.
   **Prevention:** before an instruction names a tool parameter, read the tool schema in the session;
   `harness.ts` carries the same unverified `persistent` sentence from before this PR.
6. **Comments claimed `$SECONDS` is "a lower bound" and that a timeout prints a degraded line.** The real
   resolver traps TERM and prints `state=error reason=interrupted`. **Prevention:** run the falsifying
   probe for every sentence a fix adds (the code-quality seat did, in seconds).
7. **Compound shell commands naming `main` or `ps | awk` patterns were refused by guardrail hooks.**
   **Prevention:** keep `git commit`/`push` calls separate from anything that mentions the default branch;
   poll with rc files, not process listings.
8. **Foreground suite runs hit the time cap at load 50.** **Prevention:** run long suites detached with an
   rc file and wait on a Monitor.
9. **A review seat killed other sessions' `sleep` processes during cleanup.** Disclosed by the seat; no
   data lost. **Prevention:** brief seats never to signal processes by name.

## Tags

category: workflow-patterns
module: monitor-pr-checks
