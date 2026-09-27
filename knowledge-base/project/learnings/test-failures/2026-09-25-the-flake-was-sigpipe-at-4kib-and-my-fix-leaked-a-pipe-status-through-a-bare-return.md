---
title: "The flake was SIGPIPE at ~4 KiB, and my fix leaked a pipe's status through a bare return"
date: 2026-09-25
category: test-failures
module: apps/web-platform/infra mutation batteries
issue: 8664
pr: 8848
tags: [sigpipe, pipefail, mutation-battery, flaky-test, anti-vacuity]
---

# The flake was SIGPIPE at ~4 KiB, and my fix leaked a pipe's status through a bare return

## Problem

`cloud-init-inngest-zot-pull-mutation.test.sh` sometimes reported one row as not KILLED under
`run-registered-suites.sh`, and never when run on its own. The issue blamed
`ng1-harness-row1-self-compare`, citing `MISROUTED`.

## Root cause

The issue named the wrong row. That row's PASS line ends with the literal `(MISROUTED)`, so a `grep MISROUTED`
over a run log matches it. The real rows varied from run to run, and there were two mechanisms, both SIGPIPE
under `set -o pipefail`:

- **Scorer:** `grep -E '^  FAIL' "$log" | grep -qF "$expect"`. `grep -q` exits at its first match while the
  first grep is still writing, so a row killed on its named assertion scored MISROUTED. Measured: 64 of 3,000
  runs failed on a real 5,075-byte FAIL stream.
- **Guard 1b splitter:** `sed … | awk … exit`. awk exits at the missed arm's `fi`, so sed dies, and the whole
  guard dies with no FAIL line. Measured: 33 of 3,000 runs.

The #7005 framing, "safe below the 64 KiB pipe buffer", holds only for single-write producers. `grep` and `sed`
write through stdio in ~4 KiB chunks, so the exposure starts at the first write after the reader has matched.

## Solution

- **Scorer:** `failed_on` captures the FAIL lines once and glob-matches them in bash. It aborts on grep rc ≥ 2 and
  refuses an empty needle.
- **Splitter:** awk now reads the file itself, and skipping comment lines is its first rule.
- **Deterministic regression inputs** replace a 1–2% flake:
  - a scorer self-test whose needle is followed by 1.26 MB of FAIL output;
  - a padded must-PASS row with ~160 KB of no-op code after the exit point, plus a positive control that restores
    the old piped splitter in a sandbox and requires the row to BROKE as a crash.
- **Load check:** 10 concurrent copies, load 35 on 16 cores. All 10 exited rc=0 at 61/61, with 0 non-KILLED rows.

## Key insight

**The fix repeated the defect one level up, in the verification.** `case_mutate`'s MISROUTED branch ended with a
display `grep | head -5 | sed` followed by a bare `return`. A bare `return` returns the status of the last
command, which is the display pipeline. Two harness rows run `case_mutate` inside `$(…) || die`, so a SIGPIPE in
a pure *display* line could still abort the battery.

The structural-enumeration seat found this by mapping every status that reaches a verdict or an abort. None of
the other nine seats did. The rest of the review was one gap:

- the drift pin covered only the `| grep -q` spelling;
- the crash fallback covered only BROKE;
- the padded row had no backstop.

In each case the property was "any early-exit reader, any crash-shaped verdict". Each check covered one instance.

## Session Errors

1. **`deploy-arm.sh find --wait` ran inside a foreground `timeout 900`.** The harness moved it to the background
   and it died at rc 124 before CI finished.
   - Recovery: a Monitor polling `find` without `--wait`.
   - **Prevention:** follow postmerge Phase 3 literally. Watch `find` with the Monitor tool, never a foreground
     `--wait`.
2. **#8768's own deploy arm failed with `canary_sandbox_failed`.** This is the known recurrence tracked in #8016.
   - Recovery: the next arm deployed, and `served` returned CONTAINS.
   - **Prevention:** none owed here. It is tracked in #8016, and a PR that touches no `apps/web-platform/` file
     cannot cause it.
3. **Sentry's monitors API returned 403 for every prd token, and the org list came back empty.**
   - Recovery: recorded Phase 3.5 as SKIPPED (advisory) and commented on #8090, the token-replacement work.
   - **Prevention:** postmerge's token selection should follow whichever token #8090 lands on. Until then the
     step degrades to advisory, which is correct.
4. **The planner's census of sibling scorers was keyed on `"$log"`.** It missed the `"$OUT"` sites, and the review
   later found two more outside `infra/`.
   - Recovery: #8855 was updated.
   - **Prevention:** census a defect class with the drift guard's own PATTERN over a `**` glob, never with a
     variable-name-keyed search.
5. **The fix's verification was narrower than its claim.** The bare `return`, the BROKE-only fallback, the
   grep-only pin and the unbacked padded row all had this shape.
   - Recovery: commit 21d8562f53.
   - **Prevention:** for every function whose return value is read by a caller, end each display branch with an
     explicit `return 0`. Give every deterministic regression input a positive control that restores the defect
     and requires the input to catch it.
6. **I wrote a false sentence about which census missed which sites.**
   - Recovery: corrected in the next commit.
   - **Prevention:** re-read a claim about a search against the search's actual output before writing it.
7. **`test-all.sh --print-affected-set` took longer than the 120 s foreground limit, and its selection count was
   lost.**
   - Recovery: verified through `test-all-affected.test.sh` (43/43) and the edge grep.
   - **Prevention:** run `--print-affected-set` in the background, or rely on the affected suite.
8. **I edited the battery while 10 concurrent copies were executing it.** Bash reads scripts incrementally. It was
   safe only because `sed -i` replaces the inode.
   - Recovery: none needed.
   - **Prevention:** run concurrent-load rounds from a detached worktree at the SHA under test, never the live
     worktree.
9. **`cleanup-merged` skipped the #8616 worktree because of untracked `.scratch-8616/` logs.**
   - Recovery: deleted them, and the worktree was reaped.
   - **Prevention:** keep scratch logs under `/var/tmp/<tag>`, never inside the worktree.

## Related

- #8855 (the sibling scorer sites, with a shared scorer library as the default remedy)
- #7005 (the repo-wide SIGPIPE class; its 64 KiB framing is refined above)
- `knowledge-base/project/learnings/test-failures/2026-09-23-my-sigpipe-regression-guard-pinned-the-file-size-not-the-cause.md`
