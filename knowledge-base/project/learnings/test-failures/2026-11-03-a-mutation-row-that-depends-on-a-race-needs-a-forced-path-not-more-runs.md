# Learning: a mutation row whose detection depends on a race needs the event forced by construction

## Problem

`apps/web-platform/infra/inngest-luks-key-probe.test.sh` row G4-2 drops the `0:0:141` tr-SIGPIPE
allowance from `inngest-cutover-flip.sh` and expects `pred_early_exit_rc` to go RED. The predicate
only reds if `tr` writes after the cryptsetup stub has already exited (PIPESTATUS `0 0 141 4`), a
race: about 4 in 10 runs on CI, about 1 in 200 on a fast local host. Twenty natural runs therefore
missed it about 90% of the time locally, `expect_red` recorded a `fail()`, and the exact
`EXPECTED_ASSERTIONS=158` pin read 157 (#11752). CI passed, which is why it sat red only for
local runs and some runners.

## Solution

Fold ONE forced run into the same predicate (no assertion line added, count stays 158): a PATH-prepended
`tr` shim, gated on the probe's exact argv (`-d \n`), that drains stdin (so sed and head do not take
SIGPIPE first), touches a marker, runs `kill -s PIPE $$`, then `exit 99`; every other `tr` call
`exec`s the absolute real `tr`. A missing marker counts as `bad`. The shim's paths and the real `tr`
travel as env vars through a quoted heredoc, so nothing needs escaping.

## Key Insight

When a mutation row's RED depends on an event a race produces, raising the run count only changes
the probability. A 0.5% event needs about 1500 runs for 99.9%. Make the status exist by construction
and keep the natural runs as a bonus. Four details made the forced path trustworthy:

1. Gate the shim on the exact argv. The script runs `tr` at two other sites and the shim is on PATH
   for the whole tick.
2. Drain before dying. Without it 1 run in 200 read `0 141 141 4` (head wrote after the shim died),
   which would put the PRISTINE predicate RED about 0.5% of the time.
3. A marker proves the shim ran. A missing interpreter makes `execvp` fall through to the real tr
   silently.
4. End the shim with `exit 99` after the `kill`. A kill that does not land would otherwise read as
   `0 0 0 4`, indistinguishable from a healthy pristine run; with `exit 99` it is a loud mismatch.
   Review found this; neutering the kill in a scratch copy now reds the pristine row.

## Session Errors

- **`Monitor` called without loading its schema** — Recovery: ToolSearch select, retry. Prevention: load deferred tools before the first call.
- **Five sequential 60 s suite runs in one foreground call exceeded 180 s and were moved to the background** — Recovery: Monitor on the per-run logs. Prevention: use a background command plus Monitor for any loop of suite runs.
- **fixture-relative-assert baseline moved 19 to 20 although the plan predicted no delta** — Recovery: `assert_fixture_dir "$WORK"` in the writing window rather than regenerating the baseline. Prevention: run the fixture ratchets on any edit to a `*.test.sh` before the first commit (work Phase 0.5 item 6.6 already says so).
- **PRODUCER_JOIN reason text said "never drains first" for a shim that does drain** — Recovery: reworded after review. Prevention: write the reason from the shim's actual first statements.
- **Plan claimed the sed-side `141:0:0` arm stays covered by the G4-1 mutant; G4-1 replaces the whole arm list, so it cannot see one dropped arm** — Recovery: structural-enumeration seat found it, plan and suite comment corrected, recorded as an accepted pre-existing gap. Prevention: before writing "X stays covered by Y" in a Guard Contract, drop X alone and run Y.
- **A structural review seat ended without delivering a report** — Recovery: `SendMessage` asking for the report with no further tool calls. Prevention: put "your final message is the deliverable" in the spawn prompt (already in review/SKILL.md).
- **An idle-mtime Monitor declared a still-running seat finished** — Recovery: waited for the seat's own completion notice. Prevention: never infer completion from file mtime.
