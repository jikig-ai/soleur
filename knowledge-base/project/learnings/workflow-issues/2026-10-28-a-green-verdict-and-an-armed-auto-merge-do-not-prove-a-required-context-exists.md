# Learning: a green CI verdict plus an armed auto-merge does not prove every required context reported

## Problem

PR #11254 sat OPEN with auto-merge armed, `ci-head-verdict.sh verdict` = `full-decided ... green-test`, `mergeable = MERGEABLE`, and was never entered into the merge queue (`mergeQueueEntry: null`) for about 70 minutes (CI green 2026-10-28T09:14Z, diagnosed 10:25Z). Three watches in a row (queue state, verdict, `gh pr checks`) all read healthy.

## Root cause

One required context, `cla-evidence`, never reported on the head SHA: its `pull_request_target` run (40656550847) had been cancelled at 08:24Z while the head was being pushed. The ruleset (`gh api repos/{o}/{r}/rules/branches/main`) lists 25 required contexts; 24 were green and one was ABSENT. GitHub does not enqueue a PR with a missing required context, and nothing prints that fact. `ci-head-verdict.sh` reports on the CI workflow run only, so its green is true and irrelevant to the missing context. A stale cancelled `CI` run on the same SHA also left five FAILURE/CANCELLED rows in the rollup, which made the real gap look like noise.

## Solution

1. Read the required contexts from the ruleset, take the latest row per name from `statusCheckRollup` (latest `completedAt`), and list any context that is absent or not SUCCESS.
2. Re-run the cancelled run that owns the absent context (`gh run rerun <id>`). Here that took about 40 seconds; the PR entered the queue within 3 minutes and merged 85 minutes later.
3. Do not sync the branch by hand and do not re-arm auto-merge; neither addresses an absent context.

## Key Insight

"All checks green" is a statement about the set you were handed. A required check that never ran is not in that set, and an armed auto-merge waiting on it looks identical to one waiting for the queue. The discriminator is a diff of `required contexts` against `latest rollup per name`, not any status field on the PR.

## Session Errors

1. **Watched a stuck PR for 70 minutes through queue-state and verdict monitors that cannot see an absent context** — Recovery: compared the ruleset's required contexts to the rollup, found `cla-evidence` ABSENT, re-ran its cancelled run — Prevention: when verdict is green and the PR is not queued within about 10 minutes, run the required-versus-rollup diff before waiting further; the tooling gap is recorded here and not filed as an issue (the CONCUR gate dissented on the proposed re-evaluation trigger, 2026-10-28, and the fail-safe is not to file). Any fix should reuse the required-context logic already in `plugins/soleur/scripts/admin-merge-ready.sh` (#8500) rather than add a second copy to `ci-head-verdict.sh`, which reads only the `test` row of `ci.yml` runs and so cannot see a context owned by another workflow.
2. **A chained `sleep 45 && gh ...` was refused by the Bash hook** — Recovery: used a Monitor with an until-loop — Prevention: already enforced by the hook; use Monitor from the start.
3. **Read `PUSH_RC=$?` after `git push | grep -v`, which is the pipe's last command's status** — Recovery: noticed before relying on it and verified the push by `git log origin/main..HEAD` — Prevention: already documented (capture `rc=$?` on its own line, never behind a filter); one-off here.
4. **Pasted two sentences from the CTO analysis comment into the ADR without the context they relied on** ("the pending A6 record" with no pointer; "the 2026-10-23 pass did not locate this page" which the ADR's own text cannot back) — Recovery: two P2s from the review panel, fixed by naming the runbook row and restating the claim as something the ADR's text supports — Prevention: for each label or negative claim lifted from an issue comment or plan into a standalone artifact, ask "can a reader of this file alone resolve it?" and anchor it to a document or to text in the file; this is the existing inherited-framing rule applied to labels, not only to causal claims.
5. **Plan and session-state text went stale against the final diff** (plan said the ADR "currently ends with" the previous addendum; planned-file count omitted `session-state.md`) — Recovery: corrected in the review fix commit — Prevention: one-off; the plan's prose describes the pre-change tree and should say so.
6. **First guess at the Hetzner cancellation-page URL returned the wrong page** (forwarded from the plan phase) — Recovery: found the live page by following the redirect and the links on the parent page — Prevention: one-off.

## Tags
category: workflow-issues
module: ship, merge-queue
