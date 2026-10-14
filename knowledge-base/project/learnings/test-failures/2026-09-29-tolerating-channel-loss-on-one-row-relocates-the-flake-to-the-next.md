# Tolerating channel loss on one row relocates the flake to the next single-channel row

## Problem

#9195: T9 in `cloud-init-inngest-provision-unit.test.sh` red'd twice under
loaded runners because it asserted on ONE row of a two-channel reporting
pair — the phone row `provision-attempt-exit-143 attempt=1` — while the
production `on_exit()` emits the kill report on both the phone and `emit`
channels, either of which can be dropped under runner starvation. The
retained artifact showed `emit provision_attempt_failed rc=143.attempt=1.`
landed at +5.0s with the phone row absent entirely — evidence loss, not
lateness, so widening the window was the wrong fix.

The first-pass fix dual-channeled the *exit* evidence — and four review seats
plus the structural-enumeration seat independently flagged the same class
one row over: the *restart* witness `provision-attempt-start attempt=2` is
phone-only, so its loss re-flakes T9 with a different FAIL line. Tolerating
loss on the row you observed does nothing for the row next to it.

## Solution

Two moves, applicable to any assertion built on best-effort append-only
evidence:

1. **Read the whole designed evidence surface, not the channel that
   happened to appear in the failure artifact.** Enumerate every row the
   assertion's *assembly* depends on — not just the predicate row, but the
   anchors the predicate is measured against (the start row a timing bound
   is anchored to, the restart row an ordering assertion compares against).
   For each, list the channels that can produce it and accept whichever
   arrives. Anchor every matcher to the attempt/generation (`attempt=1`,
   trailing-dot on `attempt=1\.` so `attempt=10` can't satisfy) or a lost
   row fixes the flake and a stale row creates a false-green.
2. **When a widened poll meets a suite bound, check the bound, not just the
   poll.** The suite ran ~351s against a 360s default `_SUITE_BOUNDS`; the
   40→90s poll widening is only reachable in the failure mode where the
   bound kills the suite first — turning a diagnostic red (with the
   timestamped teardown dump the next investigation needs) into a bare
   timeout. The fix needed a `_SUITE_BOUNDS` pin as much as the matcher.

## Key Insight

The residual-flake check is mechanical: count the rows that are
fatal-if-lost in the assertion. Before the fix: `{phone exit-143 row}` —
one. After the first-pass fix: `{phone attempt=2 start row}` — still one,
relocated. The fix isn't complete until every single-row loss either still
reds *correctly* (the property genuinely didn't happen) or has a second
channel to read. Also: `bash -n` cannot see inside an awk program string —
mawk rejected a multi-line `&&`-split condition that bash syntax-checking
passed; fixture slices, not linters, are the check for awk program edits.

## Session Errors

1. `iac-plan-write-guard` denied the first plan write for quoting a log row
   containing a systemd verb (planning subagent). **Prevention:** the guard's
   contract is known — route quoted evidence references through paraphrase
   + `iac-routing-ack` marker on first write.
2. Planning subagent had no Task/agent-spawn capability and substituted
   inline equivalents for the prescribed fan-out. **Prevention:** prescribe
   fallbacks by name in the spawn prompt when the subagent's tool set is
   constrained.
3. A `discoverability_test` named the `*.test.sh` path instead of a suite
   execution command; deepen-plan Phase 4.7 caught it. **Prevention:** the
   gate exists; no new rule needed.
4. Three review agents died on a transient free-model rate limit mid-flight.
   **Prevention:** Gate 2b's resume-don't-respawn rule worked verbatim.
5. `bash -n` passed a file whose new awk program had a mawk-illegal
   multi-line condition — the fixture-slice run caught it.
   **Prevention:** run the extractor against canned slices before committing
   any embedded-awk change (already this suite's discipline; the canary
   sang because it ran).
6. A bare `lint-window-closure-assertion.py` invocation (missing
   `--allowlist`) produced a false "pre-existing failure" reading.
   **Prevention:** covered by the existing "a guard run without the
   argument that bounds it" rule — check the CI invocation before
   attributing failures.
7. `cat tasks.md` ran in the main-repo shell instead of the worktree shell.
   **Prevention:** one-off; `cd` into the worktree per command.

## Tags

flake, test-harness, dual-channel-evidence, attempt-anchoring, awk, ci, soleur
