---
title: "An inverted-match mutant of an ancestor-walking helper ended the operator's desktop session four times"
date: 2026-10-09
category: test-failures
module: plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh + .claude/hooks/grep-q-pipe-guard.test.sh
issues: [9217]
---

# Slice S5 of the grep -q drain: the observer mutant that was not safe to run

## Problem

S5 converted 66 `producer | grep -q P` lines under `plugins/soleur/` and deleted the `plugins/soleur/*.test.sh` deferral row. The plan's observer step says to prove each converted line is *observed* by flipping it (an inversion, `grep -c` to `grep -vc`) and checking the suite goes red. One converted line is the match inside a helper in `resolve-regenerable-conflicts.test.sh` that walks `$PPID` upwards and sends SIGTERM to the outermost ancestor whose argv matches. With the match inverted, every ancestor matches, the "stop at the first non-match" never fires, and the walk ends at the top of the user's session. Run on the host, that ended the Hyprland session four times in one evening (19:04, 20:08, 20:22, 20:37). Hyprland then aborted in its own shutdown path, which is what made it look like a compositor crash, and the first three restarts were read as a flaky machine.

## What was measured

- Hyprland SIGABRT core dumps at 19:04:02 and 20:08:21, and the abort stack is `CCompositor::cleanup`, so it was already exiting. The journal showed `Exit the Session` with no logind or power-key trigger beforehand: something inside the session sent SIGTERM.
- The timestamps of the observer's own log files matched each restart. The unmutated suite was run many times (pair run, controls) with no incident.
- Inside `unshare -Urpf --kill-child --mount-proc` the test shell is PID 1 and has no ancestor, so the identical mutant is contained: the suite goes red (rc 1, two failing rows) and the session survives. The unmutated suite is 140/140 in the namespace too.
- The helper was added by PR #8631 with no discussion of the walk, and no learning, ADR or comment recorded the hazard. The plan's AC-7 and its observer paragraph prescribed the lethal mutation, and the plan said nothing about a namespace.

## Solution

1. The helper's walk is bounded at the suite's own PID (`export SOLEUR_TEST_SUITE_PID=$$`; unset means the helper signals nothing, so the signal rows fail rather than anything being killed), and the hazard and the PID-namespace rule are stated at the helper and at the match line, not only in a spec file. A no-kill rehearsal (catch-all match, `kill` replaced by a print) printed the resolver's PID, which is below the suite's, and nothing when the variable was unset.
2. The plan carries an addendum amending AC-7. The observer ran only inside the namespace.
3. Wider workflow, skill and sandbox-allocator hardening is a separate change (the operator asked for it): a helper that runs a command in a PID namespace, the rule in the mutation-seat briefs, and a scan that lists suites with an ancestor-walking signal helper.

## Key Insight

A mutation that **inverts a matcher** is safe only if the matcher bounds a blast radius that does not depend on it. A helper that signals "the outermost ancestor that matches" is bounded by its own predicate, so mutating the predicate removes the bound. Before running any mutant of a line inside a process-signalling or file-removing helper, ask what the predicate is protecting and run the mutant where nothing outside the scratch is reachable (a PID or mount namespace, a container). A plan, a brief or a seat prompt that prescribes "flip every converted line" is a claim to measure against that question, not an instruction.

Second, smaller finding from the same slice: a FAIL message that is built only when its pin trips is never executed by a green suite. A backtick pair inside a double-quoted message string is command substitution, so the round-2 edit made the guard exit 127 whenever the test-shaped pin failed, with every seat's read and a green guard run blind to it. It surfaced only because the matrix rows that trip the pin were re-run after the edit. After editing text that is built on failure, run the row that fails it.

## Session Errors

1. **Ran the inverted-match observer mutant on the host four times.** Recovery: PID namespace, bounded walk, hazard at the code, plan addendum. **Prevention:** the mutation-seat brief and the sandbox allocator carry the namespace rule (follow-on change); a plan's "flip every converted line" step names the helper-class exception.
2. **Round-2 FAIL text contained backticks in a double-quoted string (guard exit 127 when the pin tripped).** Recovery: removed; subset matrix re-run, 18 killed and the predicted green. **Prevention:** after editing any text that is built only on failure, run the matrix row that trips it; the verification seat is told to hunt text that executes when built.
3. **A matrix driver row hard-coded a line number that a review edit then shifted; the driver died at row 2b.** Recovery: the row finds its line by content. **Prevention:** drivers locate mutation sites by content, never by line number, when any edit can land between writing and running them.
4. **Monitors built on `tail -f | grep` expired silently and one run's `DONE` was missed; a `ps | grep` self-match was hook-blocked.** Recovery: read the result file directly; later monitors used an `until` loop on a done marker. **Prevention:** wait on a marker file with an `until` loop, never a tail that never exits.
5. **The ratchet lane went red on the planner's own helper script in the spec directory (a relative-fixture site).** Recovery: guarded the output dir with the canonical `assert_fixture_dir` (62/0, baseline untouched). **Prevention:** a script a planning pass drops into a spec directory is repo code to the ratchets; run the ratchet lane when it lands.
6. **evidence.md said the ratchet lane was not run locally after it was; tasks and decision text lagged the code.** Recovery: appended addenda that supersede, not in-place edits. **Prevention:** write the evidence record from the final state, and append corrections.
7. **A review seat ended without delivering a report; another could not write its report file.** Recovery: resumed with a deliver-now message; the second delivered by message. **Prevention:** already documented (mandate file delivery in the spawn prompt).
8. **Forwarded from the planning phase:** two plan-patch scripts aborted on a bad assertion before writing (fixed and re-run), `git stash list` was blocked by a hook, `markdownlint-cli2` is not installed locally (the lints that exist were run instead). **Prevention:** a planner's patch script asserts its anchor and prints the changed line back (the documented rule); read-only checks replace the missing local lint.
