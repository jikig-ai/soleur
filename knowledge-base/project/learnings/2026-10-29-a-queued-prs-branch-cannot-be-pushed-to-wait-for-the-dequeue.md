# Learning: a queued PR's branch cannot be pushed to — wait for the dequeue before a conflict fix

## Problem

A PR in the merge queue went UNMERGEABLE (conflict with a moving main). The fix was a merge-main commit pushed to the PR branch, and the push was rejected with `GH006` (the branch is protected while the PR sits in the queue).

## Solution

Do not push to an armed or queued PR. Wait until GitHub dequeues the UNMERGEABLE entry (poll the PR's `mergeQueueEntry` / `mergeStateStatus` with Monitor), then push the conflict fix, then re-arm. Before arming, merge main in and rerun the trio census so the branch is current at arm time and the entry is less likely to be dequeued in the first place.

## Key Insight

`GH006` on a queued branch is the queue holding the branch, not a permissions fault. The only way through is the dequeue.

## Session Errors

1. A push to a queued PR branch was rejected with GH006. **Prevention:** wait for the UNMERGEABLE entry to be dequeued before pushing a conflict fix.

## Tags

category: workflow-patterns
module: merge-queue, pull-request-workflow
