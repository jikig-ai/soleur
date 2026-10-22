# Learning: JUDGED_REPRODUCING_RUNS' first occupant was a disclosed-deviation judgment

## Problem

#7432's soak probe exited 5 on two `rc=124` bound-kills of `git-data-wipe-assert.test.sh` (runs
39378082716/39446197504, 363 s vs the 360 s default). The probe's reproduction clause names two literal
tests (same-suite-RED at same sha in infra-validation; rerun at -P 1 fails) — both failed, so the letter
read "non-reproducing → revert the pin". But the defect is H4 (deterministic capacity class owned to
`_SUITE_BOUNDS`), struck 2/2 counted runs on the monitor's unsharded ~181-suite -P 4 pool, and reverting
would reintroduce the ~30% serial ceiling-kill rate the pin removal exists to kill.

## Solution

CTO ruling (2026-10-20): the reproduction clause separates real defects from -P 4 flakes; an rc=124
bound-kill is a real defect with a tracked fix, so judge it reproducing-in-intent via
`JUDGED_REPRODUCING_RUNS` — bounded by three conditions required of ANY future judgment: (a)
self-attributing rc class, (b) the fix landing in the SAME PR, (c) disclosed deviation in the probe
comment + PR body. Precedent shape already existed: parity-mutation bound-killed 2/3 dry runs and the
response was a bound entry, not a revert.

## Key Insight

A probe's mechanical reproduction tests instrument "does the failure exist outside this topology" — the
wrong question for a capacity defect whose condition only exists at contention. The human-judgment channel
(run-granular, in the same file) exists for exactly this; use it with a stated bound, never silently.
Same-suite strikes on runs created BEFORE the bound merge get the same judgment by follow-up PR; a strike
AFTER the bound lands stands (the basis collapses).

## Session Errors

1. Planning subagent claimed specs artifacts (decision-challenges/tasks/evidence) absent on disk —
   Session-Summary-vs-disk drift; parent reconstructed from verified evidence. **Prevention:** verify
   claimed artifacts with `git status`/find before trusting the summary's component list.
2. Hook false-denied worktree commits (bare-root CWD resolution). **Prevention:** `git -C <worktree>`.

## Tags
category: workflow-patterns
module: scripts/followthroughs, apps/web-platform/infra
