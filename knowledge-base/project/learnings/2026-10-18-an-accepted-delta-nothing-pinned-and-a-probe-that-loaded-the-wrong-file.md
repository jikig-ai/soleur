# Learning: an "accepted" behavior delta that nothing pins, and a probe that loaded the shipped file instead of the file under test

## Problem

Slice 1 of #10331 narrowed four `except BaseException` handlers to explicit tuples and restructured twelve
silent handlers into `contextlib.suppress` or sentinel forms. The CTO ruling recorded the one real delta:
a `BaseException` subclass outside the tuple now exits 1 with a traceback instead of rc 2 (proxy) or rc 3
(scan-ancestor). It was fail-closed and unreachable in synchronous stdlib code, so it was accepted.

The 11-seat review found seven different instances of one gap. The delta was recorded as accepted, but two
docstrings still promised the old behaviour ("ANY uncaught exception reads as rc 3") and no test pinned the new
outcome. A revert to `except BaseException` was green. An accepted delta is a decision, and a decision with no
pin is indistinguishable from an oversight.

A second problem: the plan's Guard row 5 (widen the teardown `suppress(ProcessLookupError)` to `Exception`)
survived the existing probe. The first fix added a case that raises `PermissionError` from `os.killpg`, and the
mutant STILL survived. The in-process probe loaded `$PROXY_SHIPPED`, so a mutated copy passed through
`PROXY_UNDER_TEST` was never exercised.

## Solution

- State the delta in the docstrings of both scripts, in the same commit that records the ruling.
- Pin the outcome: one case per script for a `BaseException` subclass outside the tuple (proxy: rc 1, nothing on
  stdout, no child spawned, class named in the traceback; scan-ancestor: rc 1, traceback, no `UNRESOLVED`).
- Make probes load `$PROXY` (the file under test), and run the mutant to confirm the case reddens.
- Add a positive control next to a negative one: the "stdout has no `reconfigure`, so the stderr call is
  skipped" case is blind to the call never being made, so a sibling probe with `reconfigure` on both streams
  asserts both calls and `errors="surrogateescape"`.

## Key Insight

A ruling that says "accepted" closes the question only if something fails when the accepted behaviour changes.
For every delta a decision row accepts, ask what test reds if the delta is reverted. Whatever answers
"nothing" is documentation. Separately, a mutation that survives after you add a case means the case reached the
wrong file or the wrong branch. Run the mutant before believing the new case.

## Session Errors

1. **Filing gate refusals (three in a row).** The first `gh issue create` named no user-visible consequence;
   the retry used `$VAR` in `--body-file`; the third call carried a `printf` append that died with the refused
   `gh`. Recovery: `Mandated-By:` line, literal absolute path, append in its own call.
   **Prevention:** write the body file (with its `Mandated-By`/`Tracks` lines) in a separate step first, then
   run `gh issue create` alone with a literal path.
2. **Planner wrote `decision-challenges.md` rows the ruling gate rejects** (a planner finding, then a ruling with
   a parenthetical before the `<date>:`). Recovery: spawn the CTO for the technical row, reformat the other.
   **Prevention:** run `technical-ruling-gate.sh --branch` before the work phase (one-shot already does); the
   plan skill's row template should carry the exact `Ruled by CTO agent, <date>: <decision> - <rationale>` shape.
3. **A guard row survived because its probe loaded the shipped file.** Recovery: retarget the probe to `$PROXY`,
   re-run the mutant. **Prevention:** when a plan lists a mutation row, run that exact mutant before and after
   writing the covering case; a still-surviving mutant means the case is aimed wrong.
4. **`--affected` gate queued 1.5 hours behind four sibling runs.** Recovery: killed my own queued run (own
   worktree only) and left the gate to ship Phase 4 and CI. **Prevention:** run `test-all.sh --capacity` before
   launching; a queued run counts as running, so do not edit the tree while it waits.
5. **Wrong expected bytes in a new test** (`b'\xfb\xef\xbf'`; the real decode is `b'\xfb\xef?'`).
   **Prevention:** compute an expected literal with the same call before writing the assertion.
6. **Scripted multi-edit aborted midway**, leaving half the batch applied. **Prevention:** assert every anchor
   before writing anything, and `git status --short` after any scripted batch to see what actually changed.
7. **`grep --include` under the ugrep shim matched `.test.sh` for a `*.py` filter.**
   **Prevention:** use `git grep -- '<pathspec>'` for path-filtered sweeps.
8. **`pytest` unavailable locally.** `test_lint_ratchet.py` was not run here. **Prevention:** note the skipped
   suite in the PR body and rely on the CI shard; never report it green.
9. **Duplicate Monitor armed.** **Prevention:** `TaskStop` the old watch before arming its replacement.
10. **Unkept-promise Stop hook fired twice** on a closing line naming a future action.
    **Prevention:** end a paused turn with a single `Paused:` or `Blocked:` sentence.

## Tags
category: workflow-patterns
module: plugins/soleur/skills/review
