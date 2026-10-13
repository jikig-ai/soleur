# Tasks: Stage 3b of #9703 (retire the 8296 probe, route the Sentry monitor)

Plan: knowledge-base/project/plans/2026-10-12-chore-inngest-probe-heartbeat-retire-8296-probe-plan.md
Ref #9703 only; never a closing keyword.

## Phase 0 Gate (read-only)
- 0.1 Heartbeat 504655 up/paused=false via the runbook P3 read-back (no URL, no secrets)
- 0.2 Last four feeder runs span >= 45 min, all verdict=beat
- 0.3 Newest nightly heartbeat-live-reconcile (scheduled-terraform-drift.yml) after f2f5e0521b is clean
- 0.4 PR #10154 is draft, closingIssuesReferences is []

## Phase 2 Delete the probe
- 2.1 git rm scripts/followthroughs/inngest-luks-property-8296.sh and .test.sh
- 2.2 test-all.sh: remove run_suite line and its comment
- 2.3 suite-durations.tsv, suite-shard-legs.tsv (+ .tsv.n strays): remove the row
- 2.4 test-affected-kb-consumers.baseline.txt: remove two rows
- 2.5 scripts/lib/inngest-probe-row.test.sh: remove MUST_FIND element
- 2.6 Sweep git grep residuals; check followthroughs/ directory consumers for count floors
- 2.7 File follow-up issue to delete the stray scripts/*.tsv.n files (F1)

## Phase 3 Route the Sentry monitor
- 3.1 cron-monitor-alerts.tf: move label from unrouted map into monitor_ids (sorted)
- 3.2 Push, download sentry-alert-reference-expected-<run>, update alert-reference.json
- 3.3 Run sentry-monitors-audit.test.sh and the parity test

## Phase 4 Refresh comments and prose
- 4.1 betterstack-logs-alerts.tf comment block (comment-only)
- 4.2 sentry/cron-monitors.tf comment block (comment-only)
- 4.3 6894 runbook 5a passages; inngest-server.md sentence; followthrough-convention.md example
- 4.4 model.c4 clause, regenerate model.likec4.json, run c4-count-parity

## Phase 5 Ledger
- 5.1 Single-line live_verification rewrite; json parse; lint-encryption-posture

## Phase 6 Archive Stage 3a
- 6.1 git mv Stage 3a plan and spec dir into archive/ with one timestamp (not archive-kb.sh)

## Phase 7 Ship
- 7.1 Targeted tests; CI is the full-battery authority
- 7.2 After CI green, re-confirm heartbeat, ask, then remove the directive from #9703 body and re-read
- 7.3 PR body (first line: production-mutation answer), Ref #9703, Changelog, closing line; auto-close scan; assert closingIssuesReferences []
- 7.4 Enqueue; never update-branch; after merge read back, then ask before closing #9703
