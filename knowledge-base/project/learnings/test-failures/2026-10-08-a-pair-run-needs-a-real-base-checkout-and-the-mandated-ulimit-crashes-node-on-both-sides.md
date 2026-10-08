---
title: "A pair run against a pristine archive reports eight false diffs, a <= deferral row passes on slack, and ulimit -v crashes node on both sides"
date: 2026-10-08
category: test-failures
module: plugins/soleur/test + .claude/hooks/grep-q-pipe-guard.test.sh
issues: [9217]
---

# Three measured traps from the S2 drain of `plugins/soleur/test/*`

## Problem

Slice S2 of the grep -q drain converted 135 lines in 46 suites and lowered one guard row from 140 to 5. Three things in the verification path read as defects and were not, or read as green and were not.

## What was measured

1. **`git archive origin/main` is not a base.** The pair run compared a pristine archive (no `.git`, no `node_modules`) against the branch worktree. Eight suites differed in rc. Seven failed only on the archive side. Two printed their cause (`preflight-check10-suite-integrity`: `fatal: not a git repository`; `hook-input-classification-mutation`: `FATAL: could not populate the sandbox from tracked files`); for the other five the cause was not read, only shown to disappear on a real checkout. Re-run against a real detached checkout of the same SHA (`git worktree add --detach <dir> origin/main`, removed afterwards), all seven read identical rc and identical result line on both sides. A grep over the base logs for `FAIL` is also misleading here: five of those suites print a deliberate `FAIL: ... instrument self-test (EXPECTED)` line, so the first match is not the cause.
2. **The mandated `ulimit -v 6000000` crashes node.** `git-tripwire.test.sh` has a vitest arm; under the cap V8 dies (`Trace/breakpoint trap`, `fatal error: all goroutines are asleep`, rc 133) and the arm reports `want 97`. The unmodified base content run inside the worktree under the same cap fails the same assertion (24 passed, 1 failed); the branch without the cap is 25 of 25. On the archive side the arm was skipped for want of `node_modules`, which made the base look better than it was. A cap that is right for a battery of shell mutants is wrong for any suite that spawns node.
3. **A `<=` deferral row does not fail on slack.** With 5 hits, `<= 6` passes (rc 0) and `= 6` fails with `deferral ceiling is loose`. The codemod refuses `apply --write` on a `=` row, so the order is: lower the ceiling while the row is `<=`, convert, then flip to `=` as the last edit.

## Prevention

- Build the base side of a pair run from a real checkout of the base SHA, never from `git archive`; compare rc AND the result line, and read the cause of any base-side failure before counting it as a difference.
- Apply `ulimit -v` to shell mutants and to suites that spawn only shell; run node-spawning suites without it and state that in the evidence table.
- When a guard row can be `<=` or `=`, say which the residual uses and why in the comment above it.

## Session errors

- A mutation sed used `/` as the delimiter on a pattern containing `/dev/null`; it failed to parse and the mutant did not land. The did-it-land compare (`cmp` against the pristine copy) caught it before any verdict was read.
