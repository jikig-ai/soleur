# `gh pr checks` reports cancelled superseded-run jobs as `fail`

Date: 2026-11-01 · PR: #11763 · Context: merge-queue repo, `CI_DRAFT_LIGHT` draft→ready flow

## Symptom

A poll watcher on a readied PR read `gh pr checks` and counted 19 `fail` rows,
then exited "check failure". All 19 were `cancelled` jobs on the *superseded
draft run* (41275108781), not the deciding ready run (41275122359, which went
green). Marking a draft PR ready fires `ready_for_review`, which starts a new
run and cancels the in-flight draft run on the same head.

## Rule

When polling a PR's checks on this repo, scope failures to the deciding run
(the `run=` field of `ci-head-verdict.sh wait-ready-run`/`verdict` output, or
the newest `pull_request` run on the head SHA). `cancelled` conclusions on any
other run at the same head are supersession noise, never regressions. Merge
queue: on enqueue the `autoMergeRequest` is consumed (`autoMergeRequest==null`,
queue-state prints `disarmed`) — that is the queue holding the arm, not a lost
arm; `queued` + `removal=none` is the healthy state.

## Advisory checks

`affected-index-ratchet` is non-required: a `fail` row leaves the PR `UNSTABLE`
but does not block merge-queue enqueue (observed #11763 enqueueing with it red;
tracked as the #11694 flake).
