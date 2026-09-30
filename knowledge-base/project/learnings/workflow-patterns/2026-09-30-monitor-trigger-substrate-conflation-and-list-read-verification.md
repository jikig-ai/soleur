---
title: "Monitor liveness must separate trigger delivery from execution substrate — and a list read is not a create-verify oracle"
date: 2026-09-30
feature: feat-one-shot-9272-9273-9274-cron-machinery
pr: 9280
tags: [cron, sentry, monitors, github-actions, inngest, update-branch, auto-merge]
---

# Monitor liveness must separate trigger delivery from execution substrate — and a list read is not a create-verify oracle

## Problem

Three latent defects paged/discarded in one morning (post-mortem
`cron-monitors-paged-falsely-…-2026-09-30-postmortem.md`):

1. `verifyScheduledIssueCreated` verified "did the producer file its issue?"
   with ONE point-in-time `GET /issues` list read ~6 s after `gh issue create`
   returned. The label-filtered list view is eventually consistent — the row
   was created at 08:02:28Z and invisible to the read at 08:02:34Z. The false
   negative flipped `heartbeatOk=false` AND skipped artifact persistence: a
   healthy run paged red and its digest was discarded.
2. `scheduled-actions-queue-health` treated a `missed` check-in as runner
   starvation, but GitHub defers `on.schedule` workflows under org load BEFORE
   a runner is requested — measured ~4 fires/day vs `*/30` → ~47 missed-checkin
   pages/day while the probe read HEALTHY whenever it landed.
3. Armed-auto-merge `soleur-ai[bot]` PRs sat `mergeable_state: "behind"` —
   GitHub cannot auto-merge a stale head and no actor ran update-branch, so
   four consecutive daily digests never reached `main` while every monitor
   stayed green.

## Solution

- **List reads are not create-verify oracles.** Retry the list read on a
  bounded budget (3 × 12 s) and emit a non-paging `scheduled-output-late-visible`
  warn when a retry recovers — the warn is the measurement that tells you the
  lag persists, while the retry is the fix that keeps real work.
- **Delivery ≠ execution.** The "a monitor measuring the GHA queue must not be
  Inngest-dispatched" premise conflated the trigger's delivery path with the
  executor's substrate. A dispatch cron only POSTs `workflow_dispatch` — it
  needs no runner to FIRE — while the executor still lands in the measured
  queue, so the self-referential starvation signal survives the move. Keep the
  `schedule:` byte-identical as the fallback clock (the #8450 parity guard keys
  on it) and widen the check-in margin to cover the measured dispatch delivery
  (p90 ~20 min queue wait + runtime + jitter).
- **Auto-merge needs a "behind" actor.** A sweep (every 2 h) re-bases armed bot
  PRs with `PUT /pulls/{n}/update-branch`. Bound it: settle-guard (never update
  while check runs are in flight), `expected_head_sha` CAS (422 head-moved →
  quiet skip), ≤5 updates/sweep oldest-first (each merge re-`behind`s the rest
  under strict up-to-date rules — an uncapped sweep is O(N²) merge commits
  flooding the pool a sibling monitor measures), and states update-branch
  cannot fix (`dirty`/`blocked`/`unstable`) go LOUD via a dedup action-required
  issue.
- **Guard taxonomy note for update-branch:** `contents:write` on the HEAD repo
  is the grant GitHub checks for the update; the settle-guard's check-runs read
  additionally needs `checks:read` (an App token 403s without it). REST
  `user.login` is `soleur-ai[bot]` while GraphQL `author.login` is
  `app/soleur-ai` — pick the predicate for the API you're actually calling.

## Reference

- Plan: `knowledge-base/project/plans/2026-09-30-fix-cron-machinery-monitoring-integrity-plan.md`
- Issues: #9272, #9273, #9274 — soak: `scripts/followthroughs/cron-machinery-soak-9272.sh`
