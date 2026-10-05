# Learning: a flag derived from one probe gated rows that needed another, and an audited SHA does not survive a rebase

## Problem

Three suites had no recorder evidence (#9307, section 2). The recorded explanations were "the recorder cannot audit itself
inside its own network namespace" and "fails under `env -i` with no network". Measuring each suite under the real
recorder falsified both: the recorder wrapped every suite in `unshare -rn`, which maps the caller to namespace-root, and the
reaper detector refuses a privileged caller; `unshare` was simply not on the scratch PATH, so the recorder's own suite skipped
section B. Network was never the cause. The fix (probe `unshare -cn` first, stamp `idmap=`, add `unshare` to the scratch bin)
then produced its own defects in review, all in the new guards.

## Solution

- Probe `unshare -cn`, fall back to `-rn`, then bwrap; stamp `idmap=current|root|none` in the header AND the meta file;
  decide a `--mode demote` row only when the mapping is positively `current` (`idmap-root`, `idmap-unknown` otherwise).
- Hedge `scripts/test-affected-kb-consumers` (its read set is the registration corpus), declare five reads for
  `scripts/audit-suite-reads`; record the decision, costs and final table in an append-only audit-doc addendum and ADR-242 decision 19.
- Review (7 seats, then a 5-seat fix round and a verification seat): 37 raw findings, 16 unique, 0 P1. Fixed inline.

## Key Insight

1. **A flag derived by one probe must not gate rows that need a different probe.** `EXPECT_IDMAP=current` is true for
   `unshare -cn` and for bwrap; three mutation rows rewrote `unshare -cn` lines and were gated on it, so a bwrap-only host ran them
   against a needle the recorder never reaches (measured 337 passed / 2 failed). Gate a mutation row on reachability of the
   exact branch it rewrites (`HAVE_UNSHARE_C`), and make the unreachable arm a COUNTED skip that fails under CI, not an `ok_if 0`.
2. **"Unknown" must not read as the permissive state.** The first refusal was `idmap == root`; a meta with no `IDMAP` line (every
   pre-change recording, which were all root) stayed decided. Decide only on the positive value, refuse the rest, and give the replay
   builders the positive value by default.
3. **An explanation recorded in three documents is still a hypothesis.** "No network" survived a plan, an audit doc and a lib
   comment; one run under each identity falsified it. When a sandbox wrapper changes who the process is, measure under both identities.
4. **Evidence stamped with a SHA does not survive a rebase.** Rebase onto `origin/main` first, then run the recorder, then paste the
   table; the SHA is gone after the squash anyway, which is why the table is pasted verbatim.
5. **A number inherited through three artifacts is still unverified.** The plan called #9441 the tracker for a scheduled recorder check;
   it is the D4 issue (deleted-subject edges). Three review seats repeated it. `gh issue view <N> --json title` before citing.

## Session Errors

1. **Edited the recorder while a detached RED run was reading it.** Recovery: killed the run, re-ran RED against a pristine copy of HEAD's recorder. Prevention: the work skill's "unrelated edit invalidates the running suite" rule already covers this; list the processes in the worktree before any edit while a detached run exists.
2. **Armed a duplicate Monitor three times** (the supersede hook warned each time). Recovery: `TaskStop` on the earlier one. Prevention: stop the previous watcher in the same step that re-arms.
3. **Mutation rows gated on `EXPECT_IDMAP`, true on a bwrap-only host too.** Recovery: `HAVE_UNSHARE_C` flag plus counted skips. Prevention: gate a mutation row on the probe of the branch it rewrites; a reviewer question: "which host shapes reach this line?"
4. **New replay rows overwrote the meta file with `>`**, dropping the window rows (rc 4). Recovery: delete only the `IDMAP` line (`grep -v` + `mv`). Prevention: filter a fixture file, never rebuild it from its first lines.
5. **A shim row still expected `demotable` after the demote refusal was added.** Recovery: run the shim in check mode and add a demote row asserting `idmap-root`. Prevention: when a verdict gains a refusal, grep every live row that expects the verdict it can now remove.
6. **Cited #9441 as the scheduled-check tracker, inherited from the plan.** Recovery: `gh issue view` before writing the ADR; cited the umbrella's section 3 and said no separate issue exists. Prevention: title-check every issue number a plan hands over (hard rule `hr-before-asserting-github-issue-status`).
7. **The audited SHA stopped existing after the rebase.** Recovery: rebased, then re-recorded against the new head. Prevention: rebase before the evidence run.
8. **Plan scenarios and figures went stale between planning and review** (commit-coverage 51/57 became 52/58; two scenarios changed). Recovery: re-derived the figures before writing them, updated the scenarios in place. Prevention: re-run a plan-quoted measurement before it enters a durable document.

## Tags
category: test-failures
module: scripts/audit-suite-reads, scripts/lib/test-affected-paths.sh
