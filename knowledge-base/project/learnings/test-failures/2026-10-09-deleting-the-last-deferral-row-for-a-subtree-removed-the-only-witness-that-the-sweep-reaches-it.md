---
title: "Deleting the last deferral row for a subtree removed the only witness that the sweep still reaches it"
date: 2026-10-09
category: test-failures
module: .claude/hooks/grep-q-pipe-guard.test.sh + scripts/
issues: [9217]
---

# Slice S3 of the grep -q drain: three measured traps

## Problem

S3 converted 130 lines in 47 files under `scripts/` and deleted both `scripts/` deferral rows. Its own matrix (10 rows, all as predicted) and a 16-suite pair run were green. A nine-seat review then found that the end state had lost a witness.

## What was measured

1. **A `<=` row was the only thing that noticed the sweep losing a subtree.** The stale-deferral rule fails a row that has no hits, so while a `scripts/*.test.sh` row existed, excluding `scripts/lib` from `SWEEP_PATHSPEC` (1706 files swept instead of 1743) made that row stale and failed the guard. With the rows deleted nothing did, and `SWEEP_FLOOR=1400` left 343 files of slack. The real-table probe already plants one violating file under each subtree a wave took to zero; S3 did not add its own. With four canaries under `scripts/` (top level, `lib/`, `followthroughs/`, a `test-*` name) the probe fails on an excluded subtree, and also on a resurrected `scripts/*.test.sh <= 99`, `*.test.sh <= 50` or `scripts/* <= 9` row plus one covering hit, which was the matrix's known surviving mutant.
2. **A parity digest compared across two trees is only as equal as the environment.** The base clone had no `node_modules`, so every declared-edge line in the branch's `--print-selection` output carried one extra `^node_modules/.bin/` entry and all four path-set digests differed. Linking `node_modules` into the clone made three of four equal at once. The `--enumerate-commands` output also differs between trees for a legitimate reason (the relevance gate reads each tree's diff: 581 `SUITE_COMMAND` records on base, 588 on the branch, 591 suite ids on both); the claim that holds is "same 591 suite ids", not "same records".
3. **A mutation row whose `sed` fails still reports a verdict.** A resurrected-row mutant used `#` as the sed delimiter while the row text contained `#9217`; sed exited with `unknown option to s`, the guard stayed pristine, and the row printed a red result only because a leftover hit was present. The "landed" line (`landed adds=8`) counted the previous step's canary diff, so it looked like a landed mutation. Redone with a Python insert and a `cmp` against a pristine copy, the rows were real.

## Prevention

- When a slice deletes the last deferral row for a subtree, plant its canaries in the real-table probe in the same PR and mutation-prove them in both directions (an excluded subtree, and a resurrected row plus a covering hit). Put the canary line in the slice checklist for S4 to S7.
- Compare trees only after making the environment identical (link `node_modules`, create the same refs) and compare what is invariant (suite ids), not records that depend on each tree's diff.
- A mutation landing check compares the mutated file with a pristine copy of that file (`cmp -s`), never a `git diff` count that other edits can inflate; build row text with a script, not a `sed` replacement that contains the delimiter.

## Session Errors

1. **`rm -rf` of a scratch directory was blocked by the guard hook because the shell's cwd was inside the worktree.** Recovery: created a fresh directory name. **Prevention:** allocate a new scratch directory per run instead of deleting an old one.
2. **Four duplicate `Monitor` watches were armed on one file, each flagged by the supersede hook.** Recovery: stopped the extras. **Prevention:** before arming a monitor, list the session's monitors; one watch per target.
3. **Selection digests differed between base and branch because the base clone lacked `node_modules`.** Recovery: linked `node_modules`, re-ran. **Prevention:** see above (equalise the environment before comparing).
4. **Mutation rows for resurrected rows did not land (`sed` delimiter) and the "landed" counter was misleading.** Recovery: Python insert plus `cmp`. **Prevention:** see above.
5. **`grep -m1 FAIL` in a pipeline reported rc 141 for matrix row 9.** Recovery: re-ran with the guard's rc captured on its own line. **Prevention:** capture `rc=$?` before any filter, as the work skill already says.
6. **The shell's cwd reset to the main checkout after commands that used scratch directories.** Recovery: absolute paths and `cd <worktree> &&` per call. **Prevention:** already covered by the work skill's absolute-path rule.
7. **A multi-file edit script aborted on one mistyped anchor after writing two files and before the third.** The per-file assert-before-write kept each file consistent, and the assertion exposed it. Recovery: re-ran only the remaining files. **Prevention:** after any scripted multi-file edit, print `git diff --stat` and confirm every intended file changed.
8. **Two stop-hook blocks on closing text that named a future action.** Recovery: `<stop>BLOCKED: ...</stop>` with the blocking fact. **Prevention:** end waiting turns with the fact, not the intention.
9. **The plan's statement that nothing on `origin/main` touched the edited paths went stale** (#9753 touched `web2-luks-live-6931.test.sh`; hunks do not overlap). Recovery: re-ran `merge-tree` and the path intersection at review. **Prevention:** re-run the intersection after the final fetch, not only at plan time.
10. **Spec and plan text carried claims the final state falsified** (591 "records", stale base labels, S4's guard line 438 versus 439, the timeout rule, the overclaim that the PR removes the last place a new instance could hide). Recovery: corrected at review. **Prevention:** after the last measurement, grep the spec for each number and phrase the measurement changed.
