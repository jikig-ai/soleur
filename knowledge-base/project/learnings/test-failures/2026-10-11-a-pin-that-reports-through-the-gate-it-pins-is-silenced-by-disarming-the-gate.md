---
title: "A pin that reports through the gate it pins is silenced when the gate is disarmed, and a deleted selftest took the one check that was not about the tool"
date: 2026-10-11
category: test-failures
module: grep-q-pipe-guard
tags: [guard, text-pin, self-reference, review, deletion, equivalence-check, canary]
---

# Learning: S7a of the grep -q drain (tracker #9217, PR #9967)

## Problem

S7a deleted the series' codemod and its 341-line selftest, made the last two glob deferral rows file-exact, and added three pins to the guard (test canaries, return wiring, a probe-count anchor). Everything the author ran was green: a 14-row mutation matrix, the cheap lints, the ratchet lane. An 8-seat panel and two fix rounds then found 40-odd issues, none a merge blocker, almost all of them in the PR's own new pins.

## Solution and key insights

1. **A pin that reports through the gate it pins is silenced when the gate is disarmed.** The guard collects probe failures in `sweep_probe_fail` and a final `if (( ${#sweep_probe_fail[@]} == 0 ))` gate turns them into an exit status. The first return-wiring pin appended its failure to that array, so changing the gate to `>= 0` (or inserting a second `exit "$FAIL"` before it) made the pin's own failure invisible: the author's matrix rows W3 and W4 read `rc 0`. The pin on the gate and the pin on the final exit must report DIRECTLY (print `FAIL:` and `exit 1` themselves), ahead of the gate. Litmus for any check: *if the thing I verify were broken, would my failure still reach the exit code?*
2. **A deleted block holds more than its tool's checks.** Three review seats and the author assumed the 29 selftest checks were all about the codemod. Two were not: the `grep -q` versus `grep -c ... >/dev/null` exit-status equivalence table (`_eqv`, 13 rows, bash and sh), the only executable proof that the form every converted site uses keeps `grep -q`'s exit status. It never called the tool. Before deleting a block, list each check's subject and ask what claim in the file's header it backs.
3. **Two copies of one command are two chances to diverge.** The test-canary check re-ran the sweep's `git grep` listing, so an exclusion added to the scan alone left the canary green. One `sweep_git_grep` helper, called by the scan, the listing and the canary, makes the check see exactly what the scan sees.
4. **Negative evidence needs the evidence to exist.** A sweep that never ran (capture and fold wrapped in an unindented `if false`) satisfied every text pin. `SWEEP_N`, set only by the sweep, must hold a count; the pin now requires it, and `unset SWEEP_N` runs ahead of the sweep so an ambient value cannot stand in.
5. **A token count that "strips the comments" can strip the thing it counts.** Stripping ` #...` before counting `sweep_probe_fail+=(` dropped 8 fixture lines whose string arguments contain ` #1`, taking 36 to 29. The count anchors on the operator before the append instead.
6. **Know the class you cannot close and say it once.** Each review round found another statement that an editor of the guard's own control flow could insert between the pins and the gate. A text pin cannot defend code that runs after it and before the exit; the right response is a stated limit (recorded in the guard header and evidence.md), not a fourth pin per shape, because every pin moves the probe count and adds a new anchor to get wrong.

## Session Errors

1. **The first planning subagent ended after writing only a skeleton plan and no Session Summary.** Recovery: re-invoked `soleur:plan` inline once (the documented partial-artifact recovery). Prevention: none needed; the recovery in one-shot Step 1 worked as written.
2. **The plan asserted unmeasured structure and counts: "eight rows" (twelve after the change), a `codemod-gone` check that contradicted its own AC, a "line-1 population listing" that `scan_sweep` does not print, a wrong selftest range (1056-1397 versus 1051-1391).** Recovery: caught by the plan-review and review seats, fixed in the plan and evidence. Prevention: for every count or code structure a plan states, name the command that produced it (already a rule; the miss was inheriting numbers from the S6 plan).
3. **The author's own matrix scored the gate and exit pins as caught while two rows survived (W3, W4).** Recovery: ran a second matrix, saw `expected-text-present=no`, moved the pins to a direct report. Prevention: grade each row on the named failure text, never on rc alone (done; this is why it was seen).
4. **The comment-strip in the probe count dropped 8 lines (36 to 29).** Recovery: printed the lost lines, switched to an operator anchor. Prevention: when changing a counting recipe, diff the matched lines before and after, not only the number.
5. **The deleted selftest block took the equivalence checks.** Recovery: restored `_eqv` and its table, with a negative control for the sh pass. Prevention: finding 2 above.
6. **The review sandbox has no `.git`, so the guard exited 128 on the first control run.** Recovery: `git init` and a base commit in the sandbox; the review brief now says so. Prevention: briefs for any suite that derives its population from git must include the init step (it did from round 1 on).
7. **A new `lint-shell-capture-exit` finding on `_code=$(grep ...)` and a shellcheck SC2209 on `EQV_BASH=bash`.** Recovery: `|| true` and quoting. Prevention: run the cheap lints after each guard-shaped commit, before the panel (done on the second round).
8. **`markdownlint` printed usage and exit 0.** Cause: every changed file is under `knowledge-base/project/`, which `.markdownlintignore` skips, so the CLI had no files. Recovery: recognised the ignore file. Prevention: none; a usage dump with rc 0 means "no files to lint" here.
9. **The Stop hook flagged two closing messages that named an action not yet taken.** Recovery: ended the turn with an explicit `<stop>BLOCKED:</stop>` reason while waiting on background seats. Prevention: when waiting on notifications, state the blocking condition instead of a future action.
10. **A seat (history) did not write its report file because its own rules barred report files.** Recovery: its final message was the deliverable. Prevention: none; the brief already says the final message is the deliverable.
11. **A guard run from a subdirectory with a relative path fails (pre-existing: the exit-fold pin reads `${BASH_SOURCE[0]}` after the script `cd`s to the root).** Recovery: new pins use an absolute path; the old pin is untouched. Prevention: recorded as not fixed; the runner always passes an absolute or root-relative path.
12. **CI's `test-scripts (7/8)` shard went red on the dropped-consumer ratchet (`test-affected-kb-consumers`), which the local ratchet lane had printed as `SKIP reason=no-trigger`.** Cause: naming test files literally in the guard (canaries and file-exact deferral rows) makes the ratchet read each one a hop away; one canary named a runbook path and another a bare `knowledge-base` word, and the pkill test's allow-case string `knowledge-base/` became a recorded gap. Recovery: swapped two canaries for files that read nothing under `knowledge-base`, regenerated the baseline (one new `argv-code` row), ratchet 22/22. Prevention: when a change names test or script paths literally inside a suite, run `bash scripts/test-affected-kb-consumers.test.sh` once before pushing (about 95 s); a lane `SKIP` means "its trigger did not fire locally", not "CI will not run it".

## Tags
category: test-failures
module: grep-q-pipe-guard
