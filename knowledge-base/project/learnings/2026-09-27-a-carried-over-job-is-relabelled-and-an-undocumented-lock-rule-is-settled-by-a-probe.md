---
title: A carried-over job is relabelled, and an undocumented lock rule is settled by a probe
date: 2026-09-27
category: integration-issues
module: .github/actions/dispatch-web-redeploy/source-run-gate.sh
tags: [github-actions, concurrency, re-run, workflow_run, measurement, admin-merge]
issues: [8760, 9085]
---

# Learning: a carried-over job is relabelled, and an undocumented lock rule is settled by a probe

## Problem

`git-data-pin-redeploy.yml` fires on every attempt of a dispatched apply run. After "re-run failed
jobs", attempt N's follower saw the git-data job carried over from attempt 1 and redeployed a second
time (#8760). The issue proposed ignoring jobs whose `run_attempt` is lower than the follower's.
Separately, every follower entered the redeploy lock before its gate ran, so a non-rotating follower
could cancel a real rotation's pending redeploy (#9085).

## Solution

- **Measure the carried job before designing the filter.** On a real re-run (Infra Validation run
  36325677861, attempt 2), a carried-over job is RELABELLED: `run_attempt` reads 2 and it has a new
  job id, but its `startedAt`/`completedAt` are attempt 1's. The issue's `run_attempt` filter can
  never fire. The discriminator is time: the job started AND finished before the attempt's own
  `startedAt` (read from `gh run view --attempt N --json jobs,startedAt`).
- **Move the lock to the only job that acts.** The follower became a lock-free `gate` job and a
  `redeploy` job holding the concurrency group, gated on `needs.gate.outputs.proceed == 'true'`.
- **Settle the undocumented half by experiment.** GitHub's docs say a newer pending member replaces
  an older one and are silent on a job skipped by its `if:`. A throwaway branch probe measured it: a
  `needs`-gated job skipped by `if:` (run 36344295915) left another run's pending member
  (36344262803) pending, and a proceeding control (36344333068) then replaced it. The control is
  what makes the null result evidence rather than silence.

## Key Insight

A platform's re-run feature can present old work under a new label; a filter keyed on the label
(`run_attempt`) is structurally blind to it, while the time fields the platform sets cannot be
relabelled. And when a fix rests on platform behaviour the docs do not cover, a ten-minute
reversible probe with a positive control beats any amount of reasoning from adjacent documented
rules. The review's architecture seat was right to refuse the reasoning.

## Session Errors

1. **Ran `cd <detached-worktree> && gh pr merge --admin --match-head-commit` from a session anchored
   on the PR's own checkout (PR #9048).** The pre-merge hook reads the SESSION cwd, not the in-command
   `cd`, so it merged `origin/main` and pushed, moving the head twice and costing two CI cycles.
   Recovery: a separate `cd` call anchored the session in the detached worktree; the next merge went
   through. **Prevention:** corrected `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`
   (it claimed the one-call form works); anchor the session first, then merge.
2. **A comment-only edit to a `.github/workflows/` file made PR #9048 UNTRUSTED-CI for the admin
   merge path.** Recovery: reverted the comment to main's version, deferred it to the docs PR.
   **Prevention:** keep workflow-header prose out of a PR that may need `--admin`; check
   `admin-merge-ready.sh` eligibility before main starts outrunning CI.
3. **The runbook's dispatch step selected a `web-platform-release` run by commit with no arm**, caught
   by `workflow-run-deploy-invariants` G8 in CI. Recovery: cite `deploy-arm.sh`. **Prevention:**
   already recorded in the #9048 learning.
4. **The first review round's fixes needed a second pass of mutation-row repair:** adding the
   `completedAt` conjunct made three existing rows (GC8, GC9, GC6a) decided by the new check instead
   of the condition each row tests. Recovery: those rows now use the carried finish time.
   **Prevention:** when a fix strengthens a predicate, re-derive every row written against the weaker
   one (review/SKILL.md already names this).

## Tags

category: integration-issues
module: dispatch-web-redeploy
