# Tasks: merge-queue follow-ups for #9482

Plan: knowledge-base/project/plans/2026-10-05-chore-merge-queue-followups-9482-plan.md

## Phase 0: preflight (read-only)

- 0.1 Fetch origin main; confirm the queue is on and the monitor is still unrouted.
- 0.2 Re-read #9482 and #9493 for state changes.

## Phase 1: measure (no repo code)

- 1.1 Item 1: weakness-miner PRs merged after the adoption merge time (read live from #9455), queue timeline, merge_group run, stall issue (anchor `merge-queue stall: PR #N pending`), open digest PRs. Record "pending, next fire 2026-10-11T06:00Z" if none.
- 1.2 Item 2: sync-merge count per merged human PR, after (excluding #9455) and before (40 PRs); report after-mean AND before-minus-after delta (ADR break-even 1.3); caveats; one run, exact shell recorded.
- 1.3 Item 3: verdict rows for (b), (c), (d); restate operator decisions untouched; file the (c) tracking issue (evidence + denominator, per-SHA constraint, value at stake, trigger, milestone, `Ref #9482`). (d) verdict: not yet robustly measurable, re-run at 7 days or n>=30.
- 1.4 Heartbeat: job-start latency (median, max), longest start gap, gaps over 15 min, a red stall-check run alerts nobody (accepted gap); file the executor-visibility follow-up (`Ref #9493`); default-no.
- 1.5 Post ONE combined comment on #9482; one-line pointers on #9493 and #9454.

## Phase 2: route the monitor

- 2.1 `cron-monitor-alerts.tf`: remove the unrouted entry, add the monitor id to `monitor_ids` between `scheduled_membership_health` and `scheduled_nag_4216_readiness`.
- 2.2 `cron-monitors.tf`: update the comment above the monitor.
- 2.3 `alert-reference.json`: append `"2359391"` to the `cron-monitor-failure` detectorIds; verify sorted and canonical.
- 2.4 Run the routing-parity vitest, `sentry-monitors-audit.test.sh`, `c4-count-parity.test.sh`.

## Phase 3: ADR-270 record

- 3.1 Short dated block under "Canary results" linking to the #9482 comment and #9454. Do not touch Status or frontmatter.
- 3.2 Three index rows (canaries 4, 9, 10) in `knowledge-base/engineering/operations/runbooks/merge-queue-canary-log.md`.

## Phase 4: ship and verify

- 4.1 PR body first line states the production effect (apply-sentry-infra adds detector 2359391); `Ref #9482`, `Ref #9493`, no closing keywords.
- 4.2 After merge: apply run green (one in-place update, no destroy); live read shows 2359391 in the workflow detectorIds.
- 4.3 Comment on #9493 with the read-back and heartbeat decision; close #9493 by hand once the executor-visibility follow-up exists. Final summary on #9482.
