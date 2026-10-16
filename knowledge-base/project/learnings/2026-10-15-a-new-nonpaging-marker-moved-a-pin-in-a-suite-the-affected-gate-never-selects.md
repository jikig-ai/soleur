# Learning: a new non-paging marker moved a pin in a suite the affected gate never selects, and contention made two green suites red

## Problem

PR C (#10356, `Ref #10120`, `Ref #10093`) took the heartbeat URL off argv in `inngest-bootstrap.sh` and three probe scripts, and added a rate-limited `SOLEUR_CREDENTIAL_REFUSED` marker at five emit sites. Three things were only found late:

1. **A suite outside every local selection pinned the emitter count.** `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` asserts that each `SOLEUR_*` marker stays below the paging level and pins a `BASELINE_PASSES` count (74). Five new non-paging emit sites made it 79. `bash scripts/test-all.sh --affected` never returned the suite (it is not a registered suite; only `deploy-script-tests-fixed` in CI runs it), so the local lead gate and every directly-run suite were green while CI was red. CI found it, not review.
2. **The lead gate ran contended and reported two failures that were not the diff.** `test-all.sh` waited its full 3600 s for the advisory lock, logged `LOCK_CONTENDED_PROCEEDING`, and ran anyway beside three sibling runs. `scripts/test-all-infra-coverage-notice` runs each arm under `timeout 120` and failed one arm (210/211); `git-data-runcmd-rehearsal` spent its 420 s apt budget inside a docker fixture and reported its three emitter arms as "fixture starved, no claim made" (98 passed, 4 failed). Both passed standalone afterwards (211/0 and 108/0).
3. **A review pass caught claims inherited from a sibling script.** A comment said all four units run as root (the heartbeat unit runs as `deploy`), and a limiter crashed on a zero-padded stamp (`08` read as an invalid octal). Both were copied framings, not measurements.

## Solution

- Re-pinned the send-failed battery (74 to 79), verified by diffing a run against an `origin/main` extraction (same 9 cases, only the five new sites differ).
- Classified each gate failure only after a standalone re-run on a quieter machine, and recorded which failures were the sanctioned GuardA window (one row, drifted list exactly `inngest-bootstrap.sh`) versus contention.
- Compared the gate's selection to its execution by name, not by count: the 183 suites with `AFFECTED_SELECTED ... 1` in `--print-selection` are exactly the 183 rows in the timing log that were not skipped (`skip=not-affected` 449, `skip=relevance` 6).

## Key Insight

A green `--affected` gate says the diff reached the registered suites; it says nothing about suites CI runs by path (`apps/web-platform/test/infra/*.test.sh`). Any PR that adds an emitter of a marker class, or edits a script whose output a pinned battery counts, must grep the pinned-count suites for the marker name before pushing. And a gate that gave up waiting for its lock is a different instrument from one that held it: its failures are leads, not verdicts, until re-run alone.

## Session Errors

1. **Send-failed battery baseline drifted (74 to 79), found by CI, not locally** - Recovery: re-pinned, commit `583850e101`. Prevention: before pushing a change that adds a `SOLEUR_CREDENTIAL_REFUSED`/`SOLEUR_*` emit site, `grep -rn '<MARKER>' apps/web-platform/test/infra/` and run every suite it names; `--affected` does not select that directory.
2. **Merge conflict in `scripts/guard-vacuity-floor.test.sh` (`PROMOTED_FILES`) against #10294** - Recovery: kept both sides plus a rationale comment. Prevention: none beyond the existing conflict gate (one-off).
3. **Consumer limiter crashed on a zero-padded stamp** - Recovery: stamps capped at 10 digits and read with `10#`, with rows for 3599/3600 boundaries and garbage seeds. Prevention: any arithmetic over a value read from a state file goes through `10#` and a length bound; the pattern is now in three scripts and the dark-arm helper.
4. **A comment asserted "all four units run as root" (inherited from a sibling script's header)** - Recovery: corrected to the measured user (`deploy` for the heartbeat unit). Prevention: for every universal claim a diff's prose adds, name the command that falsifies it and run it (compound Phase 0.5 inherited-framing gate).
5. **Lead gate launched before the re-pin was committed, then waited about 100 minutes queued** - Recovery: killed the stale run, committed, relaunched. Prevention: commit and push before launching a gate whose result will be recorded; do not edit the tree while it runs.
6. **`--print-selection` printed `258 of 637` once, then `183 of 632` on every later print and in the gate itself** - Recovery: discarded the one print; the cause is not established (the tree and base were unchanged between prints as far as I could read). Prevention: record the selection from the same invocation the gate logs (`AFFECTED_SUMMARY` in its own log), not from a separate print.
7. **Two gate failures were contention artefacts** - Recovery: standalone re-runs. Prevention: when `LOCK_CONTENDED_PROCEEDING` appears in the log, re-run each failed suite alone before classifying it.

## Tags

category: test-failures
module: apps/web-platform/infra, scripts/test-all.sh
