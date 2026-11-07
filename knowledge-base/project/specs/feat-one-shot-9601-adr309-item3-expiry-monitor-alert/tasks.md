# Tasks: route the approval-expiry Sentry cron monitor (ADR-309 flip item 3, Ref #9601)

Plan: knowledge-base/project/plans/2026-11-07-feat-route-approval-expiry-monitor-adr309-item3-plan.md

## Phase 0 - Re-verify precondition (gate)

- [x] 0.1 Read-only GET of `monitors/scheduled-approval-expiry/`: `production` status ok, activeIncident null, lastCheckIn within margin. If not, stop and keep the unrouted entry.
- [x] 0.2 Read-only GET of `detectors/?query=scheduled-approval-expiry`: id is `2557403` (use the live id if it differs).

## Phase 1 - Terraform ledger

- [x] 1.1 `cron-monitor-alerts.tf`: insert `sentry_cron_monitor.scheduled_approval_expiry.id,` between the `scheduled_anthropic_credit_probe` and `scheduled_git_data_erasure_redrive` elements of `monitor_ids`.
- [x] 1.2 `cron-monitor-alerts.tf`: delete the `scheduled_approval_expiry` entry and its comment block from `cron_monitor_alert_unrouted`; leave the other three entries untouched.
- [x] 1.3 `alert-reference.json`: add `"2557403"` to `cron-monitor-failure.detectorIds` between `"2409332"` and `"2586358"`; one added line only.
- [x] 1.4 `cron-monitors.tf`: replace the last sentence of the comment above `scheduled_approval_expiry` (two-PR-rule wording) with a statement that it is routed into `cron_monitor_failure` (Ref #9601, ADR-309 flip item 3).
- [x] 1.5 Local gates: `terraform fmt -check`, `jq -S` canonical + sorted + length 25, Guard 1 (`sentry-cron-monitor-routing-parity.test.ts`) and `sentry-monitor-iac-parity.test.ts`.

## Phase 2 - Docs in lockstep

- [x] 2.1 ADR-309 checklist item 3: rewrite per the plan (status plus re-check; not "discharged").
- [x] 2.2 `flag-create-handover.md` item 3: identical text, byte for byte.
- [x] 2.3 ADR "Accepted deviation: cron monitor routing": append one dated sentence.
- [x] 2.4 Assert the two item-3 extracts are identical (content anchors `3. **Route the cron monitor` to `4. **Real-SDK probe`).
- [x] 2.5 `bash scripts/markdown-lint.sh --repo-sweep` clean before committing markdown.

## Phase 3 - Ship

- [ ] 3.1 Run both binding greps (must print nothing) before every push.
- [ ] 3.2 PR body: `Ref #9601` only, `## Changelog`, transient-monitors-audit-warning note, test-plan line that the slow local `--affected` battery was not awaited (CI is the gate), attribution line; `ci_cycles` once after the final push.
- [ ] 3.3 CI: infra-validation plan shows exactly one change (in-place update of `cron_monitor_failure`); reference gate PASS.

## Phase 4 - After merge (read-only)

- [ ] 4.1 `apply-sentry-infra.yml` green for the merge commit.
- [ ] 4.2 `GET workflows/?query=cron-monitor-failure`: `detectorIds` length 25 and contains `2557403`.
