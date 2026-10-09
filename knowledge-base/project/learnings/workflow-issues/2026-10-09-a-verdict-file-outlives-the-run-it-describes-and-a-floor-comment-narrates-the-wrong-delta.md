---
title: A verdict file outlives the run it describes, and a floor comment narrates the wrong delta
date: 2026-10-09
category: workflow-patterns
tags: [monitor, verdict-file, stale-notification, assertion-floor, mutant-floor, git-data-cutover, 9439]
symptoms: [monitor reported "suite finished: 143 10s" for a run that had been restarted, floor comment listed mutants the diff had deleted]
module: apps/web-platform/infra
component: tooling
problem_type: workflow_issue
resolution_type: workflow_improvement
root_cause: missing_validation
severity: low
---

# Learning: a verdict file outlives the run it describes, and a floor comment narrates the wrong delta

## Problem

Two process defects surfaced while closing the #9439 fix pass (PR #9878, git-data cutover state-matrix gaps).

1. I killed a running suite, fixed two shellcheck SC2120 warnings, deleted `r7.rc` and restarted it. The monitor armed on the FIRST run then fired `suite finished: 143 10s` — the killed run's wrapper had written its rc after my `rm`. The notice described a run that no longer mattered; reading it as the verdict would have reported a 10-second failure for a suite that passed (613, 0 failed) three minutes later.
2. The restated `MUTANT_FLOOR=138` and `FLOOR=613` were correct (both are exact `-ne` checks and the suite passed), but the comment narrative above them listed mutants the diff had deleted (`m9439-13`, `nb6`) and called the standalone-row delta "-4" without saying it was -5 plus a new row. The test-design verification seat caught it.

## Solution

- Kill, THEN wait for the killed wrapper to exit, THEN remove the verdict file, THEN start the run. Better: key the verdict file on the run (`r7-<pid>.rc`) so a late write from a killed run cannot be read as the new run's verdict. Before trusting a monitor notice, `ls -la` the verdict file and check the log's tail — a 10 s run of a 3 min suite is not a verdict.
- Restate a floor comment from the diff, not from memory: `git diff -U0 | grep -E '^[+-].*(mutate|exec_row|g2n_row)'` for the mutant delta, and name each added and removed row. The floor VALUE is self-checking (exact `-ne`); the NARRATIVE is not, so it needs the same derivation discipline.
- Run the lint set (`shellcheck -S warning`, `actionlint`) BEFORE launching a multi-minute suite, not alongside it: a lint fix edits the file under the running suite and invalidates the run.

## Key Insight

A notification is authoritative for liveness, never for verdict (already in the work skill) — and the artifact the notification points at can be stale in a second way: a killed run's wrapper still writes its exit file after you cleared it. And an exact-equality floor makes the number self-verifying while leaving the comment that explains it free to rot; treat the comment as a derived artifact.

## Session Errors

1. **Write hook rejected the first plan write over two command-shaped phrases** (forwarded from session-state). Recovery: reworded, no opt-out. **Prevention:** none needed — the hook worked; keep command-shaped phrases out of plan prose.
2. **Doppler-phrase hook block on a heredoc.** Recovery: reworded. **Prevention:** none — the hook worked as designed.
3. **Python raw-string syntax error in an inline edit.** Recovery: wrote the edit as a script file. **Prevention:** multi-line edits containing quotes go in a script file, not an inline heredoc one-liner.
4. **Edited the suite under a running baseline, invalidating that run.** Recovery: killed and restarted. **Prevention:** hold rule — no edits to the worktree while a suite or seat runs against it; lint first, then launch.
5. **NB6 failed after a PROBE_FAILED text change** (the new text contained `mode=unfreeze`). Recovery: assert `confirm=UNFREEZE-GIT-DATA` absence instead. **Prevention:** when changing operator-facing text, grep the suite for assertions on the old tokens before editing.
6. **Stale mutant anchors (fz4, g2v-12) after a case-arm rewrite.** Recovery: re-anchored, re-verified the diff-line count per mutant. **Prevention:** after rewriting a block, re-drive every mutant whose anchor lives in it before the suite run.
7. **Wrong rollback simulation (reverted one of two commits).** Recovery: redid with both. **Prevention:** `git rev-list origin/main..HEAD` to enumerate the commits before `git revert --no-commit`.
8. **`WF-notify-plain` referenced `nsteps` before it was defined.** Recovery: moved the row later. **Prevention:** none beyond the suite catching it.
9. **Started the suite past two shellcheck SC2120 warnings** (`case_vo_mustpass`, `case_vo_refuse`). Recovery: dropped the `"$@"` forwarding, killed, restarted. **Prevention:** `shellcheck -S warning` must print clean before a multi-minute run; do not chain `echo "lint clean"` after a command whose warnings exit 0.
10. **A monitor notice from the killed run (`143 10s`) read as the new run's result.** Recovery: checked the verdict file and log tail, found the new run alive, re-armed. **Prevention:** see Solution (run-keyed verdict file).
11. **`pgrep -f` blocked by the self-matching hook.** Recovery: `source plugins/soleur/scripts/lib/proc.sh` and `list_runs`/`kill_mine`. **Prevention:** none — the hook worked.
12. **Floor comment narrative drifted from the diff** (review P3). Recovery: restated from the row delta. **Prevention:** see Solution.
13. **A hand-rolled monitor synced a queue-armed PR twice** (earlier in this session, a different PR). Recovery: stopped syncing; delivered a resume prompt to fix `sync-pr-behind.sh` and the ship skill text. **Prevention:** queue guard in `sync-pr-behind.sh` with a fixture test (not yet implemented; owner asked only for the prompt).

## Tags
category: workflow-patterns
module: apps/web-platform/infra
