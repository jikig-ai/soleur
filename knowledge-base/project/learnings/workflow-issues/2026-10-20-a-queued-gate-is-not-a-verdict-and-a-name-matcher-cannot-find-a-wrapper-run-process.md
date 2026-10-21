# Learning: a queued gate is not a verdict, and a name matcher cannot find a wrapper-run process

## Problem

Removing the `DRAWDOWN` constant from the lint ratchet (#10583) was a small change, but the pipeline around it
produced four process stumbles:

1. `affected-tests.sh` delegated to `test-all.sh --affected`, which parked behind other worktrees' runs on the
   advisory lock (`LOCK_WAIT_HEARTBEAT ... position=5`). It ended `AFFECTED_GATE_BUDGET_DEFERRED` after about 33 minutes.
   That line is a deferral, not a pass.
2. To stop my queued run, `kill_mine test-all` and `list_runs test-all` reported "no processes match", because the
   running process was the `affected-tests.sh` wrapper chain, not a process named `test-all`.
3. My Monitor waited for `suites passed|AFFECTED_RC|EXIT=` and expired after 9 minutes, because the wrapper's real
   terminal lines were `AFFECTED_GATE_BUDGET_DEFERRED` and `AFFECTED_GATE ... reason=budget-deferred`.
4. A review seat's P2 contradicted a recorded CTO ruling (F1). The protocol routes that to the ruling's owner, not to the lead.

## Solution

- Read the wrapper's own terminal marker (`AFFECTED_GATE ... reason=...`) and treat `budget-deferred` as "CI is the
  gate", never as green. The local battery for this change was the 320-test ratchet suite plus both `--check` commands.
- Find a stuck run by what it holds, not by its name: `fuser -v <logfile>` lists every process with the log open,
  then `readlink /proc/<pid>/cwd` confirms the worktree before signalling anything.
- Match a Monitor on the union of the wrapper's terminal lines, including its deferred and refused verdicts.
- Send the dissent to the CTO agent in one batched spawn with the seat reports; it amended F1 to
  `name == "user-ruff"` (the `auto` member of `USER_SCOPES` never reaches the renderer) and upheld F2 with a comment.

## Key Insight

A gate wrapper has more than two outcomes. "Deferred", "refused" and "queued" all look like silence to a
predicate written for pass or fail, and they all read as success to a hurried reader. Name every terminal line
the wrapper can print before waiting on it.

## Session Errors

- **The affected gate queued 33 minutes and ended budget-deferred.** Recovery: relied on the targeted suites and CI.
  **Prevention:** run `bash scripts/test-all.sh --capacity` before launching the gate and treat a contended box as "CI decides".
- **`kill_mine` / `list_runs` could not see the wrapper-run gate.** Recovery: `fuser` on the log plus `/proc/<pid>/cwd`.
  **Prevention:** identify processes by the file they hold open when the command name is a wrapper's.
- **The Monitor condition matched none of the wrapper's terminal lines.** Recovery: read the log tail directly.
  **Prevention:** enumerate the wrapper's terminal markers (`grep -n 'echo "AFFECTED_GATE' plugins/soleur/scripts/affected-tests.sh`) before writing the wait.
- **Stop hook flagged first-person "holding" closings.** Recovery: ended with a `Paused:` sentence naming the one thing awaited.
  **Prevention:** when waiting on background seats, end with `Paused: <what>` rather than a future-tense promise.
- **Plan and tasks kept the superseded `name in USER_SCOPES` after the F1 amendment.** Recovery: swept the plan, tasks and
  session-state in `1ad8fbb341`. **Prevention:** after amending a ruling, grep the superseded phrase across the feature's own records.

## Tags
category: workflow-issues
module: lint-ratchet, review pipeline
