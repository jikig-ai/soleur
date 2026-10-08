---
title: "A pair run against a pristine archive reports false diffs, and the mandated ulimit -v aborts vitest on both sides"
date: 2026-10-08
category: test-failures
module: plugins/soleur/test + .claude/hooks/grep-q-pipe-guard.test.sh
issues: [9217]
---

# Two measured traps from the S2 drain of `plugins/soleur/test/*`

## Problem

Slice S2 converted 135 lines in 46 suites. The verification path produced eight rc differences between a pristine base and the branch; none was a regression.

## What was measured

1. **`git archive origin/main` is not a base.** The pair run compared a pristine archive (no `.git`, no `node_modules`) against the branch worktree, and eight suites differed in rc. Seven failed only on the archive side (two printed their cause: `fatal: not a git repository`, `could not populate the sandbox from tracked files`); re-run against a real detached checkout of the same SHA they read the same rc and result line on both sides. The first `FAIL` line in a base log is often a deliberate `FAIL: ... (EXPECTED)` instrument self-test line, not the cause, and archive-side wall times are not comparable because the suites aborted in seconds.
2. **The mandated `ulimit -v 6000000` aborts vitest, not node in general.** `git-tripwire.test.sh` has a vitest arm; under the cap the vitest worker isolate aborts with rc 133 ("Failed to reserve virtual memory for CodeRange" in `node::worker::Worker::Run`), and the arm reports `want 97`. The "all goroutines are asleep" line in the same log is the Go-built esbuild child, not V8. A plain `node -e`, a 200 MB `Buffer`, `esbuild --version`, `vitest --version` and `bun -e` all run fine under the same cap. The unmodified base content run inside the worktree under the cap fails the same assertion (24 passed, 1 failed); the branch without the cap is 25 of 25. On the archive side the arm was skipped for want of `node_modules`, which made the base look better than it was.

## Prevention

- Build the base side of a pair run from a real checkout of the base SHA, never from `git archive`; compare rc AND the result line, and read the cause of any base-side failure before counting it as a difference. Do not compare wall times across an archive-side failure.
- Apply `ulimit -v` to shell mutants and to suites that spawn only shell; run any suite that starts a vitest worker without it, and state that in the evidence table.
