# Learning: a guard for a three-line registration move tripped three repo gates, and the first cold reading ran without its dependencies

## Problem

#12013 (PR #12228): the local affected gate was about 3100 s cold; the remaining tail was `ci-pr-affected-replay-a`, which started 1.3 ks into the pool phase because registration order decides start order in the pooled runner. The fix is three moved `run_suite` lines plus a guard. The change was small; the verification around it produced most of the session's errors.

## Solution

- Moved the three arms to the first position of the first `if want_scripts` block of `scripts/test-all.sh`. The guard is section 7 of `scripts/lib/test-suite-lanes.test.sh`, over the real `--enumerate-commands all` stream: arm set derived from the label prefix, bare-battery check by label or argv without a range flag, `*` scan, and two runner-copy mutants (arms back in the glob loop; an unclassified suite registered above the arms).
- Measured one control and one treatment of the same pinned diff in private clones: pool phase 2703 s to 1882 s, `replay-a` start 1296 s to 0 s. The 600 s bar is not met (cold gate 2134 s), so the PR is `Ref #12013`.

## Key Insight

Verification code written to guard a small change is the largest and least-audited part of the diff, and repo-wide gates that the author's own suite cannot see check it. Run the census-shaped gates before the first commit of any edit to a `*.test.sh` that names a suite or a table.

## Session Errors

1. **First cold reading ended at +526 s: the private clone had no `node_modules`, so the web-platform arm refused.** Recovery: link the worktree's installs into the clone, discard the reading, restart. **Prevention:** a private-clone measurement driver must link the worktree's installs (recorded in `measurements/summary.txt`); a reading that ends before its pool phase would is invalid, not a result.
2. **`${tok_of[$l]:-*}` turned the replay arms' legitimately empty token set into `*`**, and the live check went RED on a pristine tree. **Prevention:** use `${var-default}` when empty is a value; keep the fail-closed default only for a key the map lacks.
3. **The guard rewrite tripped three gates its own suite could not see:** a literal range flag (shard-totality census), exec-shaped replay path text and literal shard-table names (replay-affected ratchet recorded transitive new pairs), and a redirect without an adjacent `assert_fixture_dir` (fixture-relative scanner). **Prevention:** after editing such a suite, run `scripts-shard-totality`, `ci-pr-affected-replay.py ratchet` and `fixture-relative-assert` before committing; a note now sits in the guard header.
4. **A mutation harness split its pattern on the pipe character while the pattern contained a double pipe:** the mutant was garbled and "killed" for the wrong reason; a second mutant was a no-op (a `:` prefix) and read as SURVIVED. **Prevention:** pass old and new text as Python arguments, not shell-split strings; before a SURVIVED becomes a finding, ask whether the mutation changed behaviour.
5. **The ADR said the last 370 s were "the web-platform group's suites"; the stamped log shows suites registered after the `*` barrier.** It was written from a plausible assumption and caught by the performance seat. **Prevention:** attribute a tail only from the per-suite start and end table (now committed as `*.suites.tsv`).
6. **The scheduler control suite was red under load 40 and green alone (64/0).** One-off timing flake. **Prevention:** re-run a red control alone before treating it as baseline.
7. **Armed duplicate Monitors, and hooks blocked `sleep` and a self-matching process search.** One-off. **Prevention:** one Monitor per target; poll with an until-loop.
8. **The stop hook fired twice because closing text named a next action without taking it.** **Prevention:** end a legitimate wait with a `Paused:` sentence naming the external event; otherwise do the step.
9. **`stale-accept` in the replay ratchet came from `main`, not the branch** (a sibling PR deleted the row). **Prevention:** merge `origin/main` before diagnosing a ratchet failure on a row the diff never touched.
10. **The plan-phase subagent filed #12231 (a GitHub write) without being told.** Required by the plan skill's deferral tracking; recorded here so the operator sees it.

## Tags
category: workflow-issues
module: scripts/test-all.sh, scripts/lib/test-suite-lanes.test.sh
