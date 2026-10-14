---
module: scripts/lib/test-contention.sh + scripts/test-contention.test.sh
date: 2026-09-22
problem_type: design_defect
component: shell_fd_semantics
symptoms:
  - "`exec {fd}>>file 2>/dev/null` silenced EVERY later >&2 banner in the process — rc stayed 0, LOCK_ACQUIRED vanished"
  - "a kill -9'd waiter still held its queue ticket: the orphaned `flock -w` child had inherited the ticket fd"
  - "sanitizing TC_RUNTIME_CEILING_S to the default broke a sibling-count test that reads the RAW value to decide fail-open"
root_cause: shell_semantics_misread
resolution_type: code_fix
severity: high
status: closed
tags: [bash, flock, fd-inheritance, exec-redirection, fail-open, advisory-lock, fifo-queue, test-harness]
synced_to: [review]
issue: 8579
pr: 8596
---

# `exec` redirection is permanent, fds outlive their owner's death, and a sanitized knob is not the raw knob

## Problem

#8579 put a FIFO ticket queue in front of `test-all.sh`'s advisory lock.
Three defects surfaced while building it — all shell-semantics misreads, all
invisible to rc:

1. **`exec {fd}>>"$f" 2>/dev/null` redirects the CALLING SHELL, not the exec.**
   `exec` with redirections only applies them all permanently. The
   `2>/dev/null` meant to suppress a failed open instead silenced stderr for
   the rest of the process — every `>&2` diagnostic vanished while the
   function returned 0. Symptom: `tc_acquire` succeeded but emitted no
   `LOCK_QUEUED`/`LOCK_ACQUIRED`, looking like a silent skip. Fix:
   `{ exec {fd}>>"$f"; } 2>/dev/null` — the group scopes the suppression.
   (Review later confirmed `eval "exec ${fd}>&-" 2>/dev/null` in
   `session-state.sh` is NOT the same bug — there `2>/dev/null` binds to
   `eval` and ends with it.)

2. **fd inheritance holds a lock past the holder's death.** The design relies
   on kernel release of a ticket `flock` when the owner dies — but children
   that inherited the fd keep it held. A waiter killed mid-`acquire_lock`
   left its `flock -w` subprocess holding the ticket until the child's `-w`
   resolved; a `kill -9`'d test waiter whose last statement was exec'd was
   fine, one whose shell persisted was not. Two consequences baked into the
   implementation: the heartbeat subshell must `exec {_TC_TICKET_FD}>&-` on
   entry (an orphaned heartbeat must not pin a dead run's queue slot), and
   suite children deliberately DO inherit the fd so the ticket lives for the
   run's lifetime. Release is bounded by the child's own lifetime — never a
   wedge, but never instant either.

3. **Normalizing a knob globally redefined a reader's contract.**
   `TC_RUNTIME_CEILING_S` sanitization (`=~ ^[0-9]+$ || =14400`) at module
   load looked like hygiene — but `tc_report`'s sibling filter deliberately
   reads the RAW value: an unusable ceiling must DISABLE the filter (count
   every sibling — fail-open to honest capacity), and the test pins exactly
   that. Sanitized to the default, `abc` filtered out stale siblings and the
   count dropped 3 → 1. Fix: leave the global raw; validate into a local at
   each arithmetic site (`_tc_ticket_sweep`'s `_sweep_ceiling`).

Also worth keeping: `$!` after `fn &` inside `$(...)` is a wrapper subshell,
not the function's process — `kill -9 $PID` misses the real ticket holder.
`( exec env ... ) &` makes the recorded pid BE the bash process.

## Prevention

- Any `exec {fd}...` with a suppression redirect: wrap in `{ ...; }` and test
  that a `>&2` line AFTER it still prints.
- Any fd-held lock whose release semantics rely on owner death: enumerate
  every child that inherits the fd (heartbeats, `flock -w` subprocesses,
  trailing `sleep`s) before claiming kernel-release timing.
- Before sanitizing an env knob at its assignment, grep every reader for a
  deliberate raw-value contract — fail-open filters depend on seeing garbage.
- Test kills: verify the recorded pid is the fd-holding process itself, not a
  wrapper — `( exec env ... ) &` or check `/proc/$pid/fd` before asserting.
