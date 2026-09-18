---
module: Development Workflow
date: 2026-09-18
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "reported 'Web Platform Release succeeded — the new code is live' while /health still returned the previous merge's build_sha"
  - "fired cron/compound-promote.manual-trigger against production that did not contain the code the fire was meant to exercise"
  - "a 50-minute Better Stack poll for a marker the running build could not emit"
  - "gh run list --commit <9-char sha> returned an empty list and the poll read empty as ALL_RUNS_COMPLETE"
  - "a Monitor cd'd into the feature worktree died with 'getwd: no such file or directory' when a sibling session's cleanup-merged reaped it at merge"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [post-merge, deploy-arm, push-arm, build-sha, adr-217, short-sha, worktree, cleanup-merged, notification-vs-verdict, inngest, anthropic-credits]
synced_to: [ship]
---

# The release run was green and production was still serving the previous build

## Problem

PR #8276 merged at 22:07:36Z as `8efd7eeb3`. Twelve workflow runs queued on the merge
commit; `Web Platform Release` went green at ~22:15Z. I told the operator the new promoter
code was live and, per the plan's post-merge step, fired `cron/compound-promote.manual-trigger`
at 22:21:21Z, then polled Better Stack for the `SOLEUR_COMPOUND_PROMOTE_OUTCOME` marker the
new code emits.

Nothing came. Fifty minutes later, `soleur:postmerge` Phase 3 read `/health`:

```
build_sha 673db24c2d91aabf77440d7f529e2c72ddfe890a   # the PREVIOUS merge (#8248)
```

The green run was the **push arm** of `web-platform-release.yml` (`event=push`: build and
publish the image). Since #5806 / ADR-217 the **deploy arm** is a separate run
(`event=workflow_run`, fired by CI *completion* on the merge commit), and that CI run was still
sitting in the GitHub runner queue. `postmerge/SKILL.md` Phase 3.7 documents this exact
two-arm split and prescribes the predicate — I read it after the fire.

The old code makes the same Anthropic call and cannot emit a marker, so the poll was
structurally unable to succeed. The real deploy landed at ~23:09Z; a second fire at 23:10:59Z
ran on the new code.

Three more instruments failed the same way in the same hour:

- `gh run list --commit 8efd7eeb3` (9-char SHA) returned an **empty** list; the poll's
  "no queued/in_progress lines" test read empty as `ALL_RUNS_COMPLETE` with zero non-success —
  the #8135 class `postmerge/SKILL.md` Phase 4 already names. Caught because it completed
  implausibly fast.
- The feature worktree was reaped by a sibling session's `cleanup-merged` the moment the PR
  merged, while a Monitor was still `cd`'d into it: `doppler run` failed with
  `getwd: no such file or directory`.
- A hooked commit hit `COMMIT_RC=124` for the second time in the session: `test-all.sh` under
  a 3600s `flock` held by two sibling worktrees; `timeout 900` killed git and the hook tree
  (`test-all.sh` + `flock`) reparented to systemd and kept the lock. The task notification said
  `exit code 0` (the trailing `tee`); the recorded rc line said 124.

## Solution

`ship/SKILL.md` merge→deploy protocol step 2 now names the predicate instead of "poll
release/deploy workflows … to success": the **deploy arm**
(`actions/runs?head_sha=<FULL merge sha>&event=workflow_run`, path
`web-platform-release.yml`, a `deploy` job present) AND `/health build_sha == merge sha`
before any post-deploy action — manual cron trigger, marker read, live-verify. Never a short
SHA (empty set), never the push arm. Post-merge steps run from a detached worktree on
`origin/main` (`git worktree add --detach .worktrees/postmerge-<pr> origin/main`), not the
feature worktree.

Recovery this session: stopped the marker poll, created the detached worktree, re-armed the
watch on `CI → deploy arm → /health build_sha`, re-fired after `build_sha` matched, re-ran the
`gh run list` predicate with the full SHA and an explicit empty-list retry branch, reaped the
orphaned hook tree by pid after confirming `/proc/<pid>/cwd`, and re-committed with the
equivalent gates run by hand and disclosed.

The production finding the fires produced is recorded on #8281 and #8293: both runs died in
`anthropic-cluster` with `Anthropic API 400 invalid_request_error: "Your credit balance is too
low"` (`req_011CfBgjSypLscvFsr4RGwFo`); `cron-anthropic-credit-probe` had logged the same
hourly since ≥20:47Z, so the account was dry before the merge. With `retries: 1` the terminal
`status=error` marker follows Inngest's retry, which had not fired 55+ minutes later.

## Key Insight

**"The release workflow is green" is a statement about a workflow run. "The artifact is
serving" is a statement about `/health build_sha`, and only the second licenses a post-deploy
action.** When a pipeline is split into arms, the arm whose name matches what you want to
know is the one that runs first and proves least. Gate on the served SHA, not on any run's
conclusion — the predicate is cheap, immutable, and already written in `postmerge` Phase 3.7.

The same hour produced three instruments that returned an answer without measuring: an empty
run list read as drained, a reaped worktree under a live watch, a notification exit code
standing in for the recorded rc. Each is an instance of
`2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran`,
and each was caught by the same move — asking what the instrument would show if the thing it
watches did not exist.

## Session Errors

1. **Read the push-arm release run as "deployed" and fired a production cron against the
   previous build.** — Recovery: `/health build_sha` in postmerge Phase 3; re-fire after the
   deploy arm. — **Prevention:** ship protocol step 2 amended (this PR): deploy arm +
   `build_sha == merge sha` before any post-deploy action.
2. **`gh run list --commit <9-char sha>` returned an empty list and the poll declared
   `ALL_RUNS_COMPLETE`.** — Recovery: full 40-char SHA plus an `EMPTY_LIST … retrying` branch.
   — **Prevention:** already in postmerge Phase 4 (#8135); the ship amendment repeats "full
   SHA, never short" at the site where the poll is written.
3. **Feature worktree reaped under a live Monitor by a sibling `cleanup-merged`.** — Recovery:
   `git worktree add --detach .worktrees/postmerge-8276 origin/main`. — **Prevention:** ship
   protocol step 2 amendment: post-merge from a detached main worktree.
4. **`COMMIT_RC=124` with the hook tree orphaned to systemd holding the flock; notification
   said exit 0.** — Recovery: read the recorded rc line, reaped by pid after a `/proc/<pid>/cwd`
   check, `LEFTHOOK=0` with gates run by hand and disclosed. — **Prevention:** third measured
   instance of `work/SKILL.md`'s notification-is-liveness-not-verdict rule; no new rule — the
   existing one worked because the rc line was written.
5. **Five BEHIND/DIRTY resyncs over ~6 hours** (three KB `INDEX.md` merge-driver DIRTYs, one
   real `rule-metrics.json` conflict resolved to main's strictly-newer snapshot after checking
   all 10 hunks, one BEHIND via `sync-pr-behind.sh`). The operator authorized admin merge for
   green-but-BEHIND; the merge API refuses DIRTY regardless of admin. — **Prevention:** none
   new; the DIRTY→local-merge path and admin-merge authorization are recorded here for the next
   busy-`main` ship.
6. **Monitor-supersede hook listed already-expired monitors as live.** — Recovery: stopped one
   defensively (no-op). — **Prevention:** none needed; harmless lag.

## Related

- `postmerge/SKILL.md` Phase 3.7 (two-arm predicate) and Phase 4 (#8135 short-SHA note) —
  both already said this; the gap was at the ship step that acts before postmerge runs.
- ADR-217 — the `web-platform-release.yml` push/deploy split.
- `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`
- `security-issues/2026-09-18-the-third-proxy-the-review-falsified-my-own-fix-and-the-learning-that-recommended-it.md`
  — the pre-merge learning of the same PR.
- `best-practices/2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md` — why an admin
  merge is not a deploy either.
- #8281, #8293 — the production finding.
