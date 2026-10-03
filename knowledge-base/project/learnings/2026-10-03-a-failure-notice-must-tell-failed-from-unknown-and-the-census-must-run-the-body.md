# Learning: a failure notice must tell "failed, nothing stranded" from "no verdict", and a workflow census must RUN the bodies it pins

## Problem

#8211 asked to "rebuild the real cutover, rollback and wipe modes". Two things went wrong in the work that followed.

1. **The brief's premise was stale.** PR #9226 had already shipped the flip, rollback, redeploy, freeze and rotate modes, and ADR-239 had made the repoint, rsync and wipe moot. A read-only audit of the twelve requested properties against `origin/main` (IMPLEMENTED / MOOT / GAP, each with file:line) turned the task into five residual gaps before any code was written.
2. **The first implementation of the residual work repeated a documented class.** The new `notify-failure` job, the finalizer's new outputs and the census over them were pinned by substring and regex rows. Review (11 seats) found that the finalizer and the notify body were never executed: deleting the `exit 1` after `recovery_failed=1`, inverting `[ -z "$words" ]`, or inserting `toJSON(github.event)` into the body env all left 48 census rows green. The class is already written down (a workflow `run:` body the diff adds is a code path with zero behavioural rows unless you give it some); the work added static rows first anyway.

## Solution

- **Execute the bodies.** `wf.py` extracts the finalizer and notify-body `run:` blocks; the suite runs them under stubs (CLI shim, two stub scripts at the paths the step calls, `${{ github.run_id }}` rendered to a constant) and compares the whole `$GITHUB_OUTPUT` content and the exit code per case: 11 finalizer cases (mode x unfreeze-outcome x marker files) and 8 notify cases. Nine executed mutants and six wiring mutants then prove the cases bite. The census rows compare whole normalized expressions and whole key sets, scan every job and every `secrets` token form (a workflow-level `env:` is inherited by every job), and pin that each `steps.<id>.outputs` reference resolves to a declared id.
- **Give a notification three states, not two.** The finalizer now writes a positive `ran=1` first. A failed run whose finalizer ran and wrote no stranded-state verdict reads as `FAILED`; only a run with NO finalizer output reads as `STATE UNKNOWN` (cancelled, timed out, runner lost). A failed `mode=unfreeze` run exports `freeze_held` (it previously exited at the mode check with nothing). A rollback whose own unfreeze succeeded skips the redundant second unfreeze, so a good rollback cannot go red on it.
- **Distinguish "absent" from "false" in a job output.** `started` is `false` only when the confirm step ran and rejected the input (a typo'd token: nothing changed, stay quiet). An absent output (runner loss, a rejected approval) pages, because "no output" is exactly the state a notify job exists to report. A job-level `if:` of `needs.X.outputs.started != 'false'` expresses it; `== 'true'` would have silenced the runner-loss case.

## Key Insight

A notify channel's value is the information in its words. When the only verdict outputs are written on failure branches, every ordinary red run falls through to the same "state unknown" text, and the operator learns to distrust the word that is supposed to mean "go check the host". Add a positive "I ran" signal so absence is informative, and make the census run the producer of that signal instead of grepping its spelling.

## Session Errors

1. **Static rows before executed rows for a workflow body (a documented class, repeated).** Eleven mutants survived a green 517-assertion suite. Recovery: executed NB/FZ rows plus whole-expression census comparisons. **Prevention:** when a diff adds or rewrites a `run:` body, the first test written is the executed case with a stub; any substring row is added only for wiring the execution cannot see.
2. **A PreToolUse write guard rejected the plan** for "operator" and "manual" phrasing near infrastructure words. Recovery: reword to "authorization-gated". **Prevention:** none needed beyond the existing guard; the plan skill already warns.
3. **A hook blocks the literal `doppler secrets set` in any Bash command, including inside test strings.** Recovery: log an opaque token (`flagwrite`) from the shim. **Prevention:** a test that needs to assert that call logs a token, never the literal.
4. **`fixture-relative-assert` went red three times on new test code** (a non-canonical indented `assert_fixture_dir`, the `trap` placed before the guard, and shell text built with `printf '... >> "$X" ...'` read as redirects). Recovery: byte-exact helper at column 0, guard before trap, quoted heredocs for stub scripts. **Prevention:** the work skill's step 6.6 already says to run the fixture ratchets before the first commit of a new `*.test.sh`; run them after every edit that adds file writes, and build stub scripts with quoted heredocs.
5. **A mutant sed anchor matched two steps** (the per-host assertion step carries the same `if:` as the probe), so `g3p-1` landed on 4 lines. Recovery: anchor on `id: probe` then `n`. **Prevention:** `mutate` already asserts the diff-line count; trust it and anchor on a step id.
6. **A renamed census row (`N-scope` to `N-jobkeys`) left a mutant naming the old prefix**, so the mutant "stayed GREEN". Recovery: retarget. **Prevention:** after renaming a census row, grep the mutant rows for the old prefix.
7. **`started` was declared, exported and pinned by a row, and nothing read it.** Four seats flagged it. **Prevention:** for every new output, grep its consumers before committing; zero readers means either use it or delete it.
8. **C4 count-parity went red** because the new notify job made `git-data-cutover.yml` the fourteenth file naming `notify-ops-email`. Recovery: edit the two `model.c4` edges and run `scripts/regenerate-c4-model.sh`. **Prevention:** a workflow that adds a Resend emitter or a new write path owes the matching `model.c4` edge in the same PR; read all three `.c4` files at plan time.
9. **A backgrounded `( ... ) &` inside a `run_in_background` Bash call returns immediately**, so the completion notification (exit 0) arrived while the 12-minute suite ran. Recovery: Monitor on the `RC=` marker line in the log. **Prevention:** the work skill's rule stands: read the rc file, never the notification.
10. **Three review seats were stopped by a session restart** and the worktree path changed under the shell. Recovery: `SendMessage` resumed each with its transcript; all three delivered. **Prevention:** brief long seats to write their report to a file so a restart loses nothing.
11. **A Stop hook rejected closing text that promised an action.** Recovery: state the real blocker in a `<stop>` tag. **Prevention:** when waiting on background agents, say what is blocked and why, without first-person commitments.

## Tags
category: workflow-issues
module: git-data-cutover, ci-census, notify-failure
