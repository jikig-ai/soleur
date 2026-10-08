---
title: "A pair run against a pristine archive reports false diffs, and the mandated ulimit -v aborts vitest on both sides"
date: 2026-10-08
category: test-failures
module: plugins/soleur/test + .claude/hooks/grep-q-pipe-guard.test.sh
issues: [9217]
---

# Two measured traps from the S2 drain of `plugins/soleur/test/*`

## Problem

Slice S2 of the grep -q drain converted 135 lines in 46 suites. The verification path produced eight rc differences between a pristine base and the branch. None was a regression, and reading them as findings would have cost a rollback of correct work.

## What was measured

1. **`git archive origin/main` is not a base.** The pair run compared a pristine archive (no `.git`, no `node_modules`) against the branch worktree. Eight suites differed in rc. Seven failed only on the archive side. Two printed their cause (`preflight-check10-suite-integrity`: `fatal: not a git repository`; `hook-input-classification-mutation`: `FATAL: could not populate the sandbox from tracked files`); for the other five the cause was not read, only shown to disappear on a real checkout. Re-run against a real detached checkout of the same SHA (`git worktree add --detach <dir> origin/main`, removed afterwards), all seven read the same rc and the same result line on both sides. A grep over the base logs for `FAIL` is also misleading here: several of those suites print a deliberate `FAIL: ... instrument self-test (EXPECTED)` line, so the first match is not the cause. The archive-side wall times are not comparable either, because the suites aborted in seconds, so a "0 s to 86 s" row says nothing about the conversion.
2. **The mandated `ulimit -v 6000000` aborts vitest, not node in general.** `git-tripwire.test.sh` has a vitest arm; under the cap the vitest worker isolate aborts with rc 133 ("Failed to reserve virtual memory for CodeRange" in `node::worker::Worker::Run`), and the arm reports `want 97`. The "all goroutines are asleep" line in the same log is the Go-built esbuild child, not V8. A plain `node -e`, a 200 MB `Buffer`, `esbuild --version`, `vitest --version` and `bun -e` all run fine under the same cap. The unmodified base content run inside the worktree under the cap fails the same assertion (24 passed, 1 failed); the branch without the cap is 25 of 25. On the archive side the arm was skipped for want of `node_modules`, which made the base look better than it was.

## Prevention

- Build the base side of a pair run from a real checkout of the base SHA, never from `git archive`; compare rc AND the result line, and read the cause of any base-side failure before counting it as a difference. Do not compare wall times across an archive-side failure.
- Apply `ulimit -v` to shell mutants and to suites that spawn only shell; run any suite that starts a vitest worker without it, and state that in the evidence table.
