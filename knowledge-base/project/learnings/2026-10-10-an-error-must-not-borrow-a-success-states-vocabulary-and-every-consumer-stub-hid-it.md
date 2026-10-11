# An error must not borrow a success state's vocabulary, and every consumer stub modelled the wrong error

**Issues:** #9728 (ADR-276 S3), #9885 · **PR:** #9885 · **Date:** 2026-10-10

## Problem

The S3 resolver `ci-head-verdict.sh` answers a closed set of six states. On a failed read (`gh` exit, rate limit) it printed
`state=no-run reason=api-error` and exited 3, on the reasoning that "a reader that only parses the state fails closed". That
holds for the merge-arming direction (nothing can read green) and is exactly wrong for the failure-alert direction: five
consumers whitelisted the six states, never looked at the exit code, and read `no-run` as "the ready run may still
register". A genuinely red `test` on a readied PR became PENDING (monitor), skipped from the required-failed exit (ship
Phase 7 poll), or tiered `ready-unarmed` (drain-prs, whose recovery is `gh pr ready --undo`) for the length of an outage.
Four of twelve review seats found it independently; the suites were green because every consumer test modelled "resolver
error" as `exit 3` with NO marker, a shape the real script never produces.

Related defects in the same PR, one class each:

- A clock-skew allowance (T minus 5 s) contradicted the measurement it cited (the ready run is created 2 to 3 s AFTER the
  event) and opened a window in which a draft push's light run read as the ready run; the header sentence "can never be
  light by construction" was a falsifiable universal nobody had falsified.
- The stall threshold (75 minutes) was justified as "above the 73-minute declared path plus the 14-minute p90 queue wait",
  which is 87.
- Three mutation harnesses credited a mutant that crashed (a bash syntax error reddens every row) as a kill; two of the
  headers said "a crash proves nothing" and implemented nothing.
- The new wait gate and resolver were wired into skills distributed to customer repos with no applicability check, so a
  repo without the mechanism would wait 300 s for a run that can never come.

## Solution

- The error marker is `state=error`, outside the closed set, so a whitelisting reader keeps its own reading; the wait verb
  prints its own marker (`reason=api-error`, exit 3) and distinguishes "could not read" from "measured negative" by the LAST
  poll only.
- Every consumer stub prints the resolver's REAL error (marker plus exit 3); a live-mode triage row runs the real script by
  its default path against a gh stub that refuses everything.
- Applicability: the resolver reads the default branch's `ci.yml` for a `draft-light` job; 404 means "not applicable", a 200
  without a top-level `jobs:` key is an error, never "not applicable" (that answer would switch the gate off).
- Skew allowance removed; threshold 120 minutes with its derivation stated; the reason token carries the number so
  consumers quote it instead of restating it.
- Harnesses: a mutant whose stderr shows a bash-level error is reported as crashed; each harness carries a survivor control,
  a non-parsing control and a runtime-failing control (`bash -n` passes) so the detector is shown to fire.

## Key Insight

A channel that carries both answers and failures needs the failure to be OUTSIDE the answer vocabulary, and the test that
proves it must use the failure the real producer emits. Two moves find this class early: (1) for every new closed set, ask
"what does the producer print when it cannot answer, and is that string in the set?"; (2) when a consumer test stubs a
producer, copy the producer's actual error output into the stub instead of inventing the shape. A residual-zero count of
`exit 3` stubs proved only that the stubs agreed with each other.

## Session Errors

1. **Resolver error marker inside the closed state set** (found by review, not by the suites) — Recovery: `state=error`,
   real-shape stubs in monitor, admin-merge, drain-prs, ship-phase-7 — **Prevention:** a producer/consumer pair gets one test
   that runs the REAL producer with its dependency failing and asserts the consumer's decision; stubs copy real output.
2. **Mutation harnesses counted a crash as a kill** (hv, ci-draft-light, soak; a learning already names this class,
   `2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`) — Recovery: stderr crash
   detector plus survivor/crash controls in all three — **Prevention:** a new mutation helper ships with the three controls
   or it does not ship; one shared helper would remove the recurrence, not filed because the three fixes closed it.
3. **A measurement-contradicting constant (5 s skew) and an arithmetic-contradicting threshold (75 vs 87 minutes)** — Recovery:
   removed / 120 with derivation — **Prevention:** a constant that cites a measurement is checked against the measurement
   file before it is written, and a header claim of the form "can never" names the command that would falsify it.
4. **Ship SKILL.md byte ceiling reached exactly (274000) and a `work/SKILL.md` sentence reverted** — Recovery: moved the
   protocol into `ship/references/ready-run-wait.md` — **Prevention:** put a multi-step protocol in a reference from the
   start; the ceiling is a design input, not a late trim.
5. **An in-place edit of a test file while a background mutation run was restoring it from a backup** (avoided by
   waiting) — **Prevention:** a mutation run that rewrites a tracked file in place owns that file until it exits.
6. **Process:** treated Monitor `sleep` commands as elapsed time (they return at once; the wait is the turn boundary) and
   used the full-command-line process matcher inside a Monitor command (blocked by hook, which also fires on prose that
   names it in a command) — **Prevention:** to wait, end the turn with a stop statement and let the event wake the session;
   write learning prose with the Write tool, not a shell heredoc.
7. **A nested triple-quoted Python heredoc broke the patch script** — **Prevention:** write multi-line patch text to a
   scratch file and read it from the script.

## Tags

category: workflow-issues
module: ci-head-verdict
