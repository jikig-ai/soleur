---
title: "ps column padding, an unguarded `ps | tr` under pipefail, and a racing own-pid probe can silently kill a bash watchdog — three failure shapes, one subshell"
date: 2026-10-07
feature: feat-one-shot-9686-watchdog-parent-death
pr: 9687
issue: '#9686'
tags: [bash, watchdog, set-e, pipefail, ps, pgrep, pid-identity, test-all]
---

# ps column padding, an unguarded `ps | tr` under pipefail, and a racing own-pid probe can silently kill a bash watchdog

## Problem

The #9686 fix-round produced three distinct silent-kill shapes inside the
`_RUN_WD` watchdog subshell (`set -euo pipefail`), each of which leaves a
run *announced but never reaped* — the worst watchdog failure class because
the log looks correct.

1. **An unguarded `ps | tr` inside `$( )` aborts the subshell on line 1.**
   `_wd_self="$(ps -o ppid= -p "$_wd_probe" | tr -d '[:space:]')"` has no
   `|| true`; under `pipefail`, `ps`'s nonzero rc propagates through the
   pipeline even though `tr` succeeded. `x="$(...)"` inherits the cmdsub's
   status → `set -e` aborts the whole watchdog before its first poll.
   Observable signature: all `ps`-shimmed test arms go vacuous (shim never
   fires), zero WARN lines, and the run completes "cleanly" — nothing ever
   polls.

2. **`ps -o <col>=` output is whitespace-PADDED.** `ps -o ppid=` returns
   `" 691177"` with a leading space. A padded `_wd_self` silently breaks
   every consumer that string-compares it: `_wd_descendants`' awk
   `a == excl` ancestor-break never matches, and `grep -vxF " 691177"`
   never matches the bare `691177` line. Net effect: the watchdog's own
   pid stays in the reap list and the first `kill -TERM` self-terminates
   the sweep mid-loop — "announced fire, surviving children" exactly.

3. **Own-pid discovery is a race on TWO axes.** `sleep 0.01 & ps -o ppid=`
   loses on a loaded box (the child exits before ps forks); and
   `$(bash -c 'echo "$PPID")'` — the pre-existing idiom, still used by the
   sibling enumerate watchdog — can report the *cmdsub subshell's* pid
   rather than the watchdog's, depending on whether bash exec-optimizes
   the inner command. A wrong `_wd_self` is worse than none: it fails the
   exclusions in BOTH directions (self leaks into the kill list AND the
   wrong pid gets filtered — potentially a real child under pid reuse).

## Solution

- Guard every external read inside a `set -euo pipefail` subshell:
  `x="$(ps ... | tr ... || true)"` — the `|| true` is load-bearing, not
  hygiene; without it `pipefail` turns a transient ps failure into a
  permanent dead watchdog.
- Normalize `ps -o <col>=` output before any string-compare consumer:
  `| tr -d '[:space:]'` for numeric columns. Exact-match filters
  (`grep -vxF`, awk `==`) are silently defeated by column padding.
- Discover own-pid via a spawned child's PPID (`sleep 0.5 &` + `ps -o
  ppid=`) — long enough to always outlive the ps fork, unambiguous on
  every bash version — and keep the nested-bash idiom only as fallback.
- Filter the watchdog's own pid out of ANY reap list assembled from
  `pgrep -P` snapshots: the watchdog IS a direct child of the runner, so
  `pgrep -P runner` returns it on every live poll; a `for ... kill` loop
  hits it in list order and self-TERMs mid-sweep.
- Test-side: never assert "children reaped" immediately after the
  announce line — the announce prints BEFORE the TERM→grace→KILL chain;
  wait for the watchdog's exit first, or the check races the grace
  window and false-fails.

## Key Insight

Every guard in a `set -euo pipefail` subshell is load-bearing, and every
exact-match comparison against `ps`/`pgrep` output is a string-compare —
both are silent when they break. The watchdog-died-quietly signature
(vacuous shims, clean run, no WARN) and the reap-truncated signature
(announce printed, children alive) are DIFFERENT bugs that the same two
primitives produce — diagnose by instrumenting with `BASH_XTRACEFD` +
`set -x` inside the subshell, never by reading the run's stdout, which
looks healthy in both cases.

## Session Errors

1. Diverged-arm fixture filename had 42 hex chars vs the 40-char
   `head_sha` — stub could not resolve the compare fixture → wrong
   verdict class. **Prevention:** derive fixture names from the same
   literal the runs.json row uses, never retype a 40-char string.
2. B1's 12s deadline was tuned to the pre-debounce ~9s chain — too tight
   post-debounce under load → widened to 25s. **Prevention:** deadlines
   bound the CHAIN (detect N polls + TERM→grace→KILL), not the wall
   clock — re-derive from chain length when the chain changes.
3. C.9's leftover assertion raced the TERM→2s→KILL grace window —
   checked survivors immediately after the announce line, which prints
   BEFORE the sweep. **Prevention:** any "children reaped" assertion
   waits for the watchdog's exit (wrapper `wait` returns), not for the
   log line.
4. `_wd_self` whitespace bug — `ps -o ppid=` padded output silently
   no-op'd the `a == excl` ancestor-break and `grep -vxF` filters →
   watchdog's own pid in its reap list → self-TERM mid-sweep.
   **Prevention:** `tr -d '[:space:]'` every `ps -o <col>=` read that
   feeds a string-compare.
5. `ps | tr` pipefail abort — unguarded `$(ps … | tr)` propagated ps's
   failure under `pipefail` → `set -e` killed the watchdog on its first
   statement. **Prevention:** `|| true` inside every `$( )` in the
   watchdog — verify by tracing, not by the run's exit.
6. Probe lifetime race — `sleep 0.01` exits before `ps` forks → empty or
   dying watchdog depending on the guard. **Prevention:** the probe
   child outlives the read (`sleep 0.5`), never a near-zero sleep.
7. `$(bash -c 'echo "$PPID")'` reported the cmdsub's own pid, not the
   watchdog's. **Prevention:** spawned-child ppid probe; nested-bash
   idiom only as fallback.
8. Instrumentation splice hit the enumerate watchdog's `_wd_sleep=""`
   (~line 747), not the run watchdog's — one wasted debug cycle.
   **Prevention:** anchor splices on a UNIQUE nearby line (the
   `_wd_probe` line), not a repeated variable init.
9. A `pgrep` full-command-line match was blocked by the self-match hook
   during debugging — the invoking wrapper's own argv carries the
   pattern. **Prevention:** capture the pid at spawn rather than
   pattern-matching process tables from inside a tool call.
10. Manual repro fixture `sleep 617.DBG` was an invalid sleep arg.
    **Prevention:** fixture sleep tokens must be numeric.

## Deferred scope-out

- The enumerate watchdog (`_ENUM_WATCHDOG`, ~line 747 in test-all.sh)
  uses the same `$(bash -c 'echo "$PPID")'` `_wd_self` idiom and the
  same `_wd_descendants` excl dependence — the identical latent
  self-TERM/self-exclusion hazard, on a path this PR does not touch.
  Filed as #9701; never inline a different-path fix into an unrelated
  feature branch.

## Reference

- Suite: `scripts/test-all-orphan-log-retention.test.sh` — Parts B/C
  exercise every arm live; Part C's shim arms pin consecutive-vs-
  cumulative counter semantics via WARN `k/N` text.
- Probe: `scripts/followthroughs/watchdog-debounce-soak-9686.sh` —
  `gh run view --job --log` (the jobs/<id>/logs API endpoint fails on
  ANSI-bearing logs), timestamp-anchored emitted-line matching.

## Post-ship CI addendum

Two further instances of the same class surfaced in CI that local runs
masked:

- **The `tr` in the `$(ps | tr)` probe raced the disarm TERM.** On a loaded
  CI shard the watchdog's startup cmdsub was still in flight when the run's
  EXIT trap TERM'd the watchdog; the orphaned `tr` (inheriting the ignored
  SIGPIPE disposition) wrote to the dead cmdsub pipe and printed
  `tr: write error: Broken pipe` onto the run's stderr — which landed in the
  clean-run tail and broke AC8's byte-identical baseline in
  test-all-killed-classification. **Fix:** discover the watchdog pid via
  `$BASHPID` (zero forks, zero children, no race window); the spawned-child
  probe stays only as the bash-3.2 fallback. Any spawned diagnostic child
  whose output consumer is the same process that disarm kills is an EPIPE
  site under `trap '' PIPE`.
- **A bare-word grep is an integration test.** The live-parent arm's
  `grep 'orphaned'` matched the *orphan-process-reaper epilogue's*
  `look orphaned` report (unrelated subsystem firing on a dirty box) — pin
  the emitter's exact phrase (`orphaned test-all run`), not a vocabulary
  word another subsystem shares.
- **Sanctioned-grep debt:** `printf | grep -q` pipes count against the
  `grep -q` early-exit deferral ceiling even in test files — the guard's
  form table (`grep -q P <<<"$V"`) applies in `scripts/*.test.sh` too, and
  `lint-trap-tempfile-ownership` requires a `trap ... EXIT` owner for every
  `mktemp`, including per-iteration files with explicit `rm -f` paths.
