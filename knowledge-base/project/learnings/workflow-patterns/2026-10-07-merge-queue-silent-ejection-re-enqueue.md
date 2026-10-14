---
title: merge-queue entries eject silently — poll the timeline, re-enqueue on ejection
category: workflow-patterns
date: 2026-10-07
related: [ADR-267, #9636]
---

A GitHub merge-queue entry can be ejected WITHOUT a merge_group ref ever forming and WITHOUT any failing check — `isInMergeQueue` flips to false, `autoMergeRequest` is consumed (reads null), `mergeStateStatus` drifts UNKNOWN → CLEAN, and nothing in `gh pr checks` or the PR comments explains it.

Symptoms observed on #9636 (2026-10-07): `added_to_merge_queue` 09:49, `removed_from_merge_queue` 10:42 — 53 min, zero group refs under `gh-readonly-queue/main/pr-9636-*`, zero new failing checks, queue itself healthy (siblings #9684/#9598 merged in the same window).

Detection: `gh api repos/<o>/<r>/issues/<N>/timeline` — diff `added_to_merge_queue` vs `removed_from_merge_queue` vs `merged`. `gh pr checks` alone looks identical before/after (still green).

Recovery: `gh pr merge <N> --merge --auto` re-enables auto-merge and re-enqueues; the second entry formed `gh-readonly-queue/main/pr-9636-<sha>`, ran merge_group checks (~90 min under contention), and merged at 11:52Z. Do NOT loop past one re-enqueue — two identical silent ejections is a systemic queue problem to file, not retry.

Poll the timeline, not `isInMergeQueue` alone — the field also reads false transiently while the group ref builds.
