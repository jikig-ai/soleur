# Learning: a required shard whose runtime straddles its job timeout turns every merge attempt into a coin flip

## Problem

PR #12262 (a 16-line CI fix) spent ~7 hours failing to merge. Every failure was the same: one of the two required
`test-webplat` shards was cancelled at the job's 25-minute `timeout-minutes` ceiling with no assertion failing, which
reddens the required `test` aggregate and dequeues the PR. Healthy shards took 16-25 min, so each queue attempt
passed or failed on runner speed; 5 of the last 10 merge groups, across four PRs, had a cancelled shard. The
job's own comment said "~5x the measured p90 (4.37 min)", a number that had stopped being true when a 12-15 min
mutation battery landed in the same group.

## Solution

CTO ruling: a separate one-integer PR (#12279) raising the ceiling to 35 min, no matrix change under queue pressure,
the failing PR left unchanged. The review seat then falsified the comment's cause: the vitest split is only ~5 min;
the time is the mutation batteries registered as plain `run_suite` calls in the webplat group, which run in full on
BOTH shards. So the flip trigger became "pin the batteries to one shard or give them their own job", not "add a third
shard" (which would repeat them).

## Key Insight

A `timeout-minutes` that was sized from a measurement is a claim about the runtime and goes stale silently when a long
suite lands. A required shard within a few minutes of its ceiling is a flaky gate by construction, and the cost lands on
whichever PR is in the queue, not on the PR that added the slow suite. After the SECOND cancelled-at-ceiling failure with
no failing assertion, stop retrying and treat it as a systemic defect: read the job's cancel reason, compare healthy
runtimes across other PRs' groups (`gh run view <id> --json jobs`), and open the fix in its own PR.

## Session Errors

1. **Retried a timeout-edge failure twice before treating it as systemic.** The first cancel read like a flake; the
   cross-PR comparison that showed the pattern came on the fourth failure. **Prevention:** after the second
   cancelled-at-ceiling failure, run the cross-run comparison before any further rerun.
2. **A `jq` empty-vs-`null` check silently skipped the re-arm.** `--jq '.autoMergeRequest'` printed an empty line, so
   `= "null"` never matched and the guarded command did not run, with no error. **Prevention:** test emptiness with
   `-z "$(… // empty)"`, and print a line on the skipped branch.
3. **The new comment's causal claim was written without measuring it.** "The vitest split is by file count" was true
   and was not the cause; three review claims were checked, the cause was not. **Prevention:** before writing a
   cause into a comment, open the log of the slow job and read per-suite durations.
4. **A compound `gh pr merge` was rejected by a hook** ("cannot prove which head this merge lands"). **Prevention:**
   issue it bare (`gh pr merge <N> --squash --auto`) as its own call.
5. **A bot-filed "merge-queue stall" issue was counted against the PR by the net-issue-flow gate.** **Prevention:**
   close a false-positive bot issue, then record the gate override with the real reason in the PR body.

## Tags

category: ci
module: ci-workflow, merge-queue, test-webplat
