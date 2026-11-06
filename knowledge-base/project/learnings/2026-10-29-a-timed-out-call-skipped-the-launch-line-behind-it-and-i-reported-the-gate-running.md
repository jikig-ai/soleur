# Learning: a call that outlived its timeout skipped the launch line behind it, and I reported the gate as running

## Problem

Resuming #10932 item (a) (an exit-1 row in the restore engine's header table, comment-only, which arms the
~860 s registry mutation battery). One Bash call chained `bash scripts/test-all.sh --print-selection | grep ...`
and then the detached `setsid nohup ... test-all.sh > gate.log` launch. The `--print-selection` half ran past
the harness's 120 s timeout, so the whole call was moved to the background and the launch line behind it never
executed. I then told the operator the gate was running. It was not: `gate.log` and `gate.rc` did not exist.

## Solution

Launch the long gate in its own call, then confirm it exists before claiming anything:
`setsid nohup env TMPDIR=/var/tmp bash -c "... > gate.log 2>&1; echo \$? > gate.rc" </dev/null &`, then
`sleep 8; ls -l gate.log; head -c 700 gate.log`. When it queued behind a sibling worktree's run
(`LOCK_WAIT_HEARTBEAT ... position=2`), the operator chose CI (the required `test` context runs the full
battery on the PR head, ADR-183) as the gate, so the queued local run was stopped with
`source proc.sh; kill_mine test-all.sh`.

## Key Insight

A status claim about a background job is a claim about a file or a process, and a chained command's later
lines are skipped when an earlier one is moved to the background. Never put a slow command in front of the
line that launches the thing you are about to report on, and never report "running" without reading the
artifact the job should have created.

## Session Errors

1. **Reported the gate as running when its launch line never executed.** Recovery: re-launched in a dedicated
   call and read `gate.log`. **Prevention:** launch detached jobs alone, then `ls -l <log>` before saying so.
2. **`pgrep -f` blocked by the self-match hook.** Recovery: read `gate.log` directly. **Prevention:** use
   `proc.sh list_runs` or file checks, never `pgrep -f`.
3. **`proc.sh list_runs 'test-all'` and `'scripts/test-all.sh'` matched nothing / were rejected (matching is on
   the basename).** Recovery: `test-all.sh`. **Prevention:** pass the exact basename.
4. **Plan-phase CTO ruling (fix the runbook sentence, reword the W9 message) contradicted the operator's fence
   ("wording owned elsewhere").** Recovery: dropped both edits, recorded the override in
   `decision-challenges.md`, named the runbook sentence as a left-open residual. **Prevention:** a scope fence
   in the brief outranks a technical ruling; check rulings against the fence before work starts.
5. **My A2 fail-message reword ("seven header rows, exit 1 included") implied the header must list exit 1,
   though the floor counts the union with {1}.** Caught by two review seats. Recovery: restored main's string.
   **Prevention:** a reworded message must state only what its condition measures.
6. **Two Stop-hook trips on closing text that named an action not yet taken.** Recovery: ended with a
   `Paused:` sentence naming the one thing awaited. **Prevention:** say what is awaited, not what comes next.

## Tags
category: workflow-issues
module: work, review, ship
