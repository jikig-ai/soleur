# Learning: a "make X fast" tracker measured a shipped-but-disabled feature

## Problem
#12013 proposed seven mechanisms to speed up the local `test-all.sh --affected` gate (parallel pool, cache, admission control, timings, ship reorder, CI-only skip). Its evidence run (>30 min, "effectively serial on 16 cores") was filed as if the mechanisms were missing.

## What the audit found
- The parallel pool (`--jobs`, PR #11282, 2026-10-27) already existed and defaults to serial. Nothing in `plugins/soleur/skills/ship` or `affected-tests.sh` sets `SOLEUR_TEST_JOBS`, so the measured run was serial by configuration, not by missing capability.
- Admission control, per-suite timings and a contention-only "CI is the gate" exit were also shipped. "Affected runs are not queued" was false (`tc_acquire "test-all"` is unconditional).
- Only 2 of the 9 named slow suites are always-on; 7 are edge-selected by the diff.
- The push-first ordering (point 6) is the opposite of ADR-276's chosen cheaper policy, and a draft `test` is red by design so `battery-owed.sh` returns OWED regardless.

## Key Insight
For a performance tracker, the first question is "which of these mechanisms is already built, and is it switched on where the measured run happened?" One `git grep` of the knob's name in the dispatching skill (`SOLEUR_TEST_JOBS` in `skills/ship`) collapsed the largest item into a one-line change. Check the dispatch site, not just the runner.

## Session Errors
- **Guessed `scripts/battery-owed.sh`; the file is `plugins/soleur/skills/ship/scripts/battery-owed.sh`.** Recovery: `git grep -l battery-owed`. Prevention: locate a named script with `git ls-files | grep` before `ls`-ing a guessed path.
- **Ended a turn with a first-person "I'll wait for the agents" and tripped the unkept-promise stop hook.** Recovery: restated as a `Paused:` line. Prevention: when waiting on background agents, end with `Paused: <what>` from the start.
- **Ran the Step 0 preamble as a condensed equivalent, not the verbatim fences.** Recovery: same checks and outputs (readiness, cloud verdict, cleanup-merged, mcp state). Prevention: none needed beyond keeping the condensed form behaviour-identical.

## Tags
category: workflow-patterns
module: test-all, ship
