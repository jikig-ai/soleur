---
title: A watchdog's own teardown order decides whether its escalation fires — and a one-generation sweep leaves lock-fd-holding grandchildren
date: 2026-09-28
category: logic-errors
module: scripts/test-all.sh
tags: [watchdog, process-supervision, pid-reuse, flock, exit-trap, bash, termination-order]
issue: 8993
pr: 9034
---

# Learning: a watchdog's own teardown order decides whether its escalation fires

## Problem

Architecture review on PR #9034 found three mechanism gaps in the parent-death
watchdog added to `test-all.sh`:

1. **Fire-order inversion.** The watchdog's reap ran TERM-children → TERM-runner →
   wait → KILL-runner → KILL-children. The runner's EXIT trap — which bash runs on
   untrapped SIGTERM — calls the watchdog's own disarm. So a TERM-resistant suite
   child (the wedge class the reap exists for) survived: the runner's disarm killed
   the watchdog mid-grace and the `-9` leg never ran.
2. **Blind to runner death.** The watchdog polled only the PARENT. A `SIGKILL`ed
   runner while the parent lived left the watchdog holding inherited stdout/stderr
   fds — a gone-but-held-pipe deadlock against the parent's never-EOF pipe reader.
   And once the runner is dead, `pgrep -P <runner>` enumerates nothing: children
   reparent to init, so the sweep had to already know who they were.
3. **Single-generation sweep.** `pgrep -P` enumerates direct children only.
   A suite's vitest/worker grandchildren inherit the same lock fd (`_TC_TICKET_FD`)
   and would survive a direct-child reap, still holding the contention ticket the
   whole mechanism exists to release.

## Solution

- **Escalate the children to completion BEFORE signaling the runner:**
  TERM-children → grace → KILL-children → TERM-runner → grace → KILL-runner.
  The runner's trap only disarms the watchdog after nothing is left to escalate.
- **Poll the runner too.** On runner death, reap the *snapshotted* child set
  (refreshed each poll while the runner is still enumerable), then exit — there is
  no runner left to signal and the pipe-inheritance deadlock is gone.
- **Walk ancestors, not children.** `_wd_descendants` runs one `ps -eo pid=,ppid=`
  pass and, per pid, walks the ppid chain until it hits a root or the excluded
  pid — transitive reaping in a single table read, no per-generation pgrep loop.

## Key Insight

A supervisor's kill order isn't an implementation detail — it IS the mechanism.
Any teardown that disarms the supervisor (an EXIT trap, a `finally`, a deferred
close) must land strictly AFTER every escalation the supervisor might still owe.
And for process trees, liveness checks and child enumeration must be *snapshot*
discipline: the set you need to kill is precisely the set that becomes
unenumerable at the moment you need it.

Fixture note (orphan-log-retention test): `pgrep -f`-style sweeps self-match on a
shared box — the fixture sleeps carry a per-run `617.$$` token; and
`( bash script ) &` gets bash's exec optimization (the subshell execs the script
directly, so the wrapper pid *is* the runner) — a trailing `wait` defeats it.

## Tags

category: logic-errors
module: scripts/test-all.sh
