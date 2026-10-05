# Tasks: merge-queue follow-ups for #9482

Plan: knowledge-base/project/plans/2026-10-05-chore-merge-queue-followups-9482-plan.md

## Phase 0: preflight (read-only)

- 0.1 Fetch origin main; confirm the queue is on and the monitor is still unrouted.
- 0.2 Re-read #9482 and #9493 for state changes.

## Phase 1: measure (no repo code)

- 1.1 Item 1: weakness-miner PRs merged after the adoption merge time (read live from #9455), queue timeline, merge_group run, stall issue (anchor `merge-queue stall: PR #N pending`), open digest PRs. Record "pending, next fire 2026-10-11T06:00Z" if none.
- 1.2 Item 2: sync-merge count per merged human PR, after (excluding #9455) and before (40 PRs); one run, exact shell recorded.
- 1.3 Item 3: verdict rows for (b), (c), (d); restate operator decisions untouched; file the (c) tracking issue (evidence, value at stake, trigger, milestone, `Ref #9482`).
- 1.4 Heartbeat: job-start latency (median, max), longest start gap, gaps over 15 min, whether a red stall-check run alerts; default-no.
- 1.5 Post ONE combined comment on #9482; one-line pointers on #9493 and #9454.

## Phase 2: route the monitor

- 2.1 `cron-monitor-alerts.tf`: remove the unrouted entry, add the monitor id to `monitor_ids` between `scheduled_membership_health` and `scheduled_nag_4216_readiness`.
- 2.2 `cron-monitors.tf`: update the comment above the monitor.
- 2.3 `alert-reference.json`: append `"2359391"` to the `cron-monitor-failure` detectorIds; verify sorted and canonical.
- 2.4 Run the routing-parity vitest, `sentry-monitors-audit.test.sh`, `c4-count-parity.test.sh`.

## Phase 3: ADR-270 record

- 3.1 Short dated block under "Canary results" linking to the #9482 comment. Do not touch Status or frontmatter.

## Phase 4: ship and verify

- 4.1 PR body first line states the production effect (apply-sentry-infra adds detector 2359391); `Ref #9482`, `Ref #9493`, no closing keywords.
- 4.2 After merge: apply run green (one in-place update, no destroy); live read shows 2359391 in the workflow detectorIds.
- 4.3 Comment on #9493 with the read-back and heartbeat decision; close #9493 by hand. Final summary on #9482.
