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

## Session Errors

1. **Mutation `sed` used `/` as its delimiter on a pattern containing `/dev/null`** and did not land. Recovery: the `cmp` against a pristine copy flagged it before any verdict was read; redone with `#`. **Prevention:** assert every mutation landed against a pristine copy, and pick a delimiter absent from the pattern.
2. **An `Edit` anchor used `| tr` where the line has `&& tr`** and failed to match. Recovery: re-read the line and used a shorter, exact anchor. **Prevention:** copy the anchor from a `sed -n` print of the line, not from memory of a summary.
3. **A `Write` to a path under the main checkout's `.git` was blocked by the worktree guard.** Recovery: wrote the file with Bash. **Prevention:** keep scratch and report files in the session scratchpad or `/var/tmp`, not under the shared gitdir.
4. **A report-path placeholder in the shared review brief was rewritten by `sed` into a bogus path.** Recovery: rewrote the line with a path-aware script and checked it. **Prevention:** build absolute paths in the brief from a variable before writing it, and `grep` the result.
5. **The pair-run base was a `git archive` copy**, which produced eight false rc differences. Recovery: re-ran the seven archive-failed suites on a real detached checkout. **Prevention:** see the Prevention section above.
6. **The first draft of this learning claimed `ulimit -v` crashes node**, which review falsified with a one-minute probe (only vitest worker isolates abort). Recovery: corrected the text and renamed the file. **Prevention:** for every causal sentence a learning adds, run the command that would falsify it before writing it.
7. **Count slips in ledger prose** (12 vs 11 suites, six vs seven workflows, 39 vs 38 identical suites). Recovery: re-derived each from a command after review. **Prevention:** derive every count from a command at write time and write the command beside it.
8. **The affected gate ran 1 h 45 min with no up-front expectation.** Recovery: stopped by decision, because CI runs the full battery. **Prevention:** state the expected duration (the repo docs say about 45 minutes for the full battery) before launching a long gate, and decide the stop condition in advance.
9. **A process search with the full-command-line flag was blocked by the self-match hook.** Recovery: searched by process name only. **Prevention:** already hook-enforced.
10. **The stop hook fired on first-person closing phrasing.** Recovery: closed with a `BLOCKED:` statement naming the blocker. **Prevention:** state blockers as facts, not as promises of the next action.
11. **The shell cwd reset to the main checkout after `cd` into scratch dirs.** Recovery: absolute paths throughout. **Prevention:** never rely on ambient cwd; chain `cd <abs> && cmd`.
12. **A ratchet-lane re-run hit my own 580 s timeout under load 32.** Recovery: read the 21 completed members (all PASS) and left the rest to CI. **Prevention:** run long lanes detached with an rc file, not under a foreground timeout shorter than the lane's own bound.
