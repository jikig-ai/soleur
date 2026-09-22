---
title: "GitHub Actions under-assignment: the metrics that mislead, the one that doesn't, and the monitor that watches it"
date: 2026-09-22
category: infrastructure
module: .github/workflows + scripts/actions-queue-health.sh
issue: 8450
pr: 8578
tags: [github-actions, queue, concurrency, monitoring, observability, survivorship-bias, zombie-runs, pagination]
---

# Actions queue under-assignment: what the incident taught us

## The incident

2026-09-22, minutes after the org upgraded GitHub Free→Team: ~206 queued runs,
only ~8–10 jobs executing against a 60-job entitlement, for ~90 minutes.
Nothing paged. Job-level queue wait medians (post-hoc): congestion window
106s median / 211s max over jobs that *started*; post-cleanup 8s; drained 0s.
The real signal — delivered-vs-entitled concurrency — was never computed.

## Metrics that mislead

**`run_started_at` is vacuous for queue analysis.** It stamps at workflow-run
registration, not runner pickup: `run_started_at − created_at` measured ~0s
*throughout the outage*. Do not use it.

**Job-level `started_at − created_at` is the honest wait — with survivorship
bias.** It only counts jobs that ever got a runner. During total starvation the
median looks fine because the starved jobs never appear in the sample. A wait
distribution alone cannot see "200 jobs never started."

**Neither end of the queue is a valid stall clock.** *Oldest*-queued age is
pinned open by zombies: queued runs are never reaped (live data: a 130-day-old
`schedule` run and 34-day-old `issues` runs still `status=queued`). *Newest*-
queued age is pinned shut by continuous arrivals — during the incident new
pushes kept landing, so the freshest member stayed seconds old. The robust
signal is the **median age of the live (non-zombie) members of the newest
page**: a handful of ancient tail entries cannot move it, and it only climbs
when arrivals genuinely stop being admitted.

**Plan entitlement ≠ delivered capacity.** `plan.name=team` documented 60
concurrent jobs; the scheduler delivered ~10. The gap is the monitorable
signal. A repo-scoped `GITHUB_TOKEN` cannot read `orgs/{org}.plan` (403) — a
floor fallback (Free=20) leaves a dead-band `[floor*PCT, real_cap*PCT)` that
the incident's own ~10 delivered sits inside; pin the known entitlement via an
override and let a live plan read win when it succeeds.

## Operational lessons

- **Queue hygiene ≠ capacity.** Cancelling ~90 superseded queued runs freed
  zero runner slots (queued runs hold no capacity — only executing jobs count)
  but cleared dead backlog so fresh work didn't queue behind ghosts. Needed,
  not sufficient; the resolution correlated with entitlement propagation /
  scheduler recovery, not the cleanup.
- **Bulk-cancel sort direction is a loaded gun.** An ascending `created_at`
  sort cancelled the *newest* run per workflow+branch+event group — including
  live current-head runs — instead of the oldest. Repair = re-run newest
  cancelled per group + cancel the kept-oldest. Rules: group by
  workflow+branch+event, sort newest-first, keep the newest, dry-run first,
  record every cancellation. GitHub self-heals required contexts by respawning
  check runs, but don't rely on it.
- **`concurrency:` groups with `cancel-in-progress: true` are the cheap
  prevention** — a ref-keyed group kills superseded queued+running runs at
  push time before they accumulate (61/79 workflows had them; the 18 without
  produced retrigger noise like 3 fires in 80s on one branch).
- **`gh api --paginate --jq` applies the filter per page** and prints one line
  per page — a >100-job run yields a multi-line value that crashes downstream
  arithmetic (and in this script would have exited 1, the UNDER_ASSIGNED
  contract code — a false alert). Slurp page objects instead:
  `gh api --paginate "$ep" | jq -s '[.[].jobs[] | ...]'`.
- **A monitor that needs a runner to notice runner starvation is
  self-defeating** — unless the missed run itself pages. Pair the scheduled
  workflow with a `sentry_cron_monitor` (heartbeat `if: always()`,
  `checkin_margin == interval`): a starved monitor misses its check-in and the
  external monitor pages. This is the #5542 lesson generalized — never let the
  watched system's substrate carry the watcher without an external dead-man.

## The reusable core

`scripts/actions-queue-health.sh` (PR #8578) — env-parameterized
(`REPO`/`ORG`/`QUEUE_DEPTH_ALERT`/`QUEUE_STALL_ALERT_S`/`MIN_ASSIGN_PCT`/
`CAP_OVERRIDE`/`ZOMBIE_S`), exits 0 HEALTHY|SATURATED / 1 UNDER_ASSIGNED /
2 UNKNOWN / 78 traced-with-credential. Verdicts:

- `UNDER_ASSIGNED` = live_depth ≥ 25 AND median live age ≥ 900s AND delivered
  < 50% of entitlement — the incident signature.
- `SATURATED` = deep+stalled but delivered ≥ 50% — demand problem, not GitHub.
- `UNKNOWN` on any prereq/API/parse failure — never silently HEALTHY.
- `zombie_runs` / `oldest_queued_run_s` reported as hygiene metrics.

`scheduled-actions-queue-health.yml` runs it every 30 min: UNDER_ASSIGNED →
`action-required` issue + Sentry error heartbeat; UNKNOWN → soft issue;
recovery auto-closes.

## Future-user runbook (when the monitor pages)

1. `gh api orgs/<org> --jq .plan.name` — does the entitlement match belief?
2. Re-run `scripts/actions-queue-health.sh --json` in ~15 min — plan changes
   take ~90 min to propagate through the scheduler.
3. Check for `cancelling` runs (`always()` teardown can hold jobs open) and
   org Actions policy (org-owner token needed — operator UI check).
4. Queue hygiene: cancel zombies (>24h) and superseded queued runs — newest
   per group, dry-run first.
5. If under-assignment persists >2h: GitHub Support ticket with the evidence
   bundle — `plan.name`, queued count, delivered jobs, median live age,
   window duration.

## Session errors

**First implementation used oldest-queued-job age as the stall clock.** Live
data immediately showed a 130-day-old zombie pinning it at 11.2M seconds —
the gate would have been permanently armed. Caught by running the probe
against the real API before shipping, not by the fixture tests.
**Prevention:** exercise new monitors against live data; fixtures only encode
the world as imagined.

**A head-age-only alternative would have failed the other way** — the
incident's continuous arrivals kept the newest queued run seconds old. Both
naive clock choices fail; the median-of-live-members is the defensible one.
