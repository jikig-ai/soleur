---
title: "I pinned the SUT's clock and let my instruments pad the floor — every control a clock-fix adds needs its own guard, and each new guard ships with its own blind spot"
date: 2026-10-31
category: engineering
tags: [flake, clock-pin, PATH-stub, guard-contract, mutation-testing, ambient-path, portability, set-e, grep-boundaries, anti-vacuity]
symptoms: [utc-midnight flake in a pinned rc-2 expectation, DPATH arm linking real date past the pin, instrument dispatches padding the SUT-only floor, grep Invalid character class name, empty command -v substitution aborting under set -e]
module: Plugins
component: technical-ruling-gate test suite
problem_type: test_failure
resolution_type: test_fix
root_cause: fixed-fixture-day vs live wall clock divergence across a UTC-midnight crossing
severity: medium
issue: '#11578'
pr: '#11680'
---

# I pinned the clock and let my instruments pad the floor

## Problem

`technical-ruling-gate.test.sh` captures `DTODAY` once at suite start and derives
every fixture instant from it, while the gate under test reads the live wall
clock. A merge-group run straddling UTC midnight turns a `dts 1` "tomorrow"
receipt into "today", so `receipt-future`'s pinned rc 2 reads rc 0 — a calendar
flake, never a real defect. The fix (ruled option C by the CTO seat over a
`TRG_NOW` production seam): an argv-strict `$DBIN/date` stub pinned to
`DNOON="${DTODAY}T12:00:00Z"`, so fixture time and gate time share one source of
truth and a crossing cannot move a fixture to the wrong side of "future".

## What the fix actually needed — a control per failure mode

The pin alone is silent when bypassed, so the suite grew four distinct controls,
and each one carried its own defect class that review enumeration found:

- **CLK bypass detector** (repin to `dts -1`, assert `delegation-invalid`/rc 1 —
  a verdict only a live stub can produce). First version never asserted *where*
  the refusal landed: a gate that calls the verifier before the ran-future check
  still returns rc 1 while the claimed property is broken. Fix: `ncalls` == 0
  pin beside it. Second blind spot: served-value asserts made *after* restoring
  DNOON are vacuous — `${DNOON%%T*}` equals real `date -u +%Y-%m-%d` on every
  calendar day. A partial passthrough on the render arm yields identical output.
  Fix: assert inside the `dts -1` window (yesterday can never equal real today).
- **Dispatch floor** (`dcalls.log` count). First version read
  `wc -l < "$DBIN/dcalls.log"` — when the stub is fully bypassed the file doesn't
  exist and the suite aborts with a cryptic shell error before `print_results`.
  Fail-closed read instead. Second instance: instrument calls through `$DBIN/date`
  (the served-value asserts themselves) logged into the same file and the floor
  was bumped to match — the "zero-slack SUT dispatches" floor then tolerated the
  SUT silently dropping up to 2 `date` calls. Fix: route instrument traffic
  through a `$TMP/ibin` copy of the stub; `$DBIN/dcalls.log` stays SUT-only.
- **AMBF ambient-arm sweep** (every `mkdr`/`rcpt`/`RCT`/`, ran` fixture must pair
  with a pinned-PATH exec). Took three grammar passes: `\b` substring hits on
  `mrcpt`, a `.`-boundary hit on `rcpt.lines`, `, ran $2` inside the `mkdr()`
  definition body, and two legitimate multi-line fixture→exec pairs. Scanning a
  suite for its own call shapes needs *space-delimited* token boundaries,
  positional-parameter (`$N`) def-body exclusion, and a lookahead window — plus
  a same-line ambient-exec flag, because the bypass shape is `mkdr f; run "$GATE"`.
- **DPATH carve-out**: `mkbin_t` reduced-PATH dirs linked the *real* `date`, so
  any future `dts +n` fixture under a DPATH case reborn the bomb under prose
  protection only. Closing it was a one-line symlink of the stub + pin files —
  but `cp` of the stub followed the pre-existing `date` symlink to the real
  binary and failed `Permission denied`; `ln -sf` is the correct primitive.

## Cross-cutting lessons

- **A `command -v` substitution is never empty-safe under `set -e`.**
  `ln -sf "$(command -v timeout)" "$d/gtimeout"` aborts on gtimeout-only hosts —
  which were exactly the hosts my conditional floor step-down claimed to serve.
  The portability guard was unreachable on the host class it existed for. Guard
  the probe, then substitute. (Same class: `print_results`'s floor must step
  down with the skipped asserts, or the anti-vacuity floor itself false-fails.)
- **Grep word boundaries are not portable.** `[[:<:]]` dies on this host's grep
  (`Invalid character class name`); `\b` is a GNU extension BSD grep ignores
  (silent vacuity on macOS). `(^|[^A-Za-z0-9_])(…)([^A-Za-z0-9_]|$)` — or a
  right-side `[[:space:]]` where the token always takes an argument — works on
  both.
- **The enum seat's rubric stands**: a map showing a path outside the guard's
  window is a P1 whether or not an instance was demonstrated. The accepted
  carve-out in the plan was real scope discipline, but "documented" is not
  "closed" — the cheap mechanical closure (symlink the stub into the reduced
  PATH) was cheaper than defending the prose.
- **Mutation-testing the clock fix paid twice**: the pinned-flake mutation
  reproduced the *exact* original signature
  (`the pristine gate gives rc 0, not the pinned 2`), and the stub-bypass
  mutation found the `wc -l <` abort that a green-only pass never reaches.

## Session Errors

1. Overlap preflight exit 2 (unmeasurable — GitHub file-list timeout); retried
   per protocol, exit 0. Transient, no fix.
2. Commit blocked by literal-path hook (variable-expanded worktree path);
   retried with the literal absolute path. Guard working as intended.
3. Commit blocked by staged+commit-in-one-call when `CLAUDE_PLUGIN_ROOT` changed
   in the same command; split `git add` and `git commit` into separate calls.
   Guard working as intended — a real friction tax worth budgeting for.
4. `cp "$DBIN/date" "$d/date"` followed the existing `date` symlink to the real
   binary → `Permission denied`; `ln -sf` fixes. One-off slip, recurring class
   (`cp` follows destination symlinks).
5. Python block-splice dropped the `assert_eq` line after the AMBF loop; floor
   tripped 502<503 and caught it — the anti-vacuity floor doing its job.
6. `[[:<:]]` invalid on host grep → `Invalid character class name`; replaced
   with portable boundary classes (lesson above).
7. AMBF needed three grammar passes (lesson above).
8. `wc -l < "$DBIN/dcalls.log"` aborted the suite on a fully-bypassed stub
   (file absent); found by own mutation battery, made fail-closed.
9. Unguarded `ln -sf "$(command -v timeout)"` aborts under `set -e` on
   gtimeout-only hosts — a pre-existing latent bug my step-down made reachable;
   fixed with a `gtimeout` fallback (lesson above).

## Recurring vs one-off triage

- **Recurring, fixed inline**: `command -v` substitution under `set -e`;
  `cp`-follows-symlink into a built dir; portable grep boundaries; served-value
  asserts that must run inside the pin window; instrument traffic polluting a
  SUT-only floor; prose-only carve-outs on guard windows.
- **One-off**: preflight transient, the splice-dropped assert, hook blocks.

## Verification

- Suite green 503/0 on this host; floor exact at 328 SUT-only dispatches.
- Mutation battery re-run post-fix: bypass mutant reds CLK + floor;
  pinned-flake mutant reproduces the original signature; all six guard-matrix
  rows kill.
- Review: 9-seat panel + 2 ADR-267 fix rounds (8 re-spawned seats); all
  actionable findings resolved; residual P3s recorded in session-state.
