# TR9 Phase 2 Tasks

## 0. Prerequisites

- [x] 0.1 ADR-033 amendment: document schedule staggering strategy, update re-evaluation criterion ("if Monday drain >4h or any function waits >120min, split pools"), document `event-` file prefix convention. Closes #4381.
- [x] 0.2 Wait for #4472 (substrate extraction) to merge — blocks C1-C5 only. **Merged as f30dbbae.**
- [x] 0.3 Extend BYOK sweep glob in `cron-no-byok-lease-sweep.test.ts` from `{cron,oneshot}-*.ts` to `{cron,oneshot,event}-*.ts`
- [ ] 0.4 Verify Sentry alert rules include email delivery to ops@jikigai.com for cron monitor missed check-ins

## 1. DELETEs

- [x] D1 DELETE `scheduled-dogfood-3155.yml`
- [x] D2 DELETE `scheduled-gdpr-gate-preflight-eval-50d.yml` — already deleted on main (cleanup from PR-G #4461)

## 2. Oneshot / Event Conversions (no Sentry cron monitor)

- [x] E1 `oneshot-f2-defer-gate-review.ts` ← `scheduled-f2-defer-gate-review.yml` (claude-eval spawn). Converted before May 29 deadline.
- [x] E2 `oneshot-recheck-4217-calibration.ts` ← `scheduled-recheck-4217-calibration.yml` (claude-eval spawn)
- [x] E3 `event-ship-merge.ts` ← `scheduled-ship-merge.yml` (claude-eval spawn). Runbook: `knowledge-base/engineering/ops/runbooks/ship-merge-trigger.md`.

## 3. Claude-code-spawn Crons (blocked on #4472)

- [x] C1 `cron-campaign-calendar.ts` ← `scheduled-campaign-calendar.yml` (Mon 16:00)
- [x] C2 `cron-content-generator.ts` ← `scheduled-content-generator.yml` (Tue/Thu 10:00) **— cascade target for T2**
- [x] C3 `cron-growth-audit.ts` ← `scheduled-growth-audit.yml` (Mon 07:00, staggered from 09:00)
- [x] C4 `cron-growth-execution.ts` ← `scheduled-growth-execution.yml` (biweekly 10:00) **— cascade target for T2**
- [x] C5 `cron-seo-aeo-audit.ts` ← `scheduled-seo-aeo-audit.yml` (Mon 11:00, staggered from 10:00) **— cascade target for T2**

## 4. Pure-TS Port Crons (independent of #4472)

- [x] T1 `cron-membership-health.ts` ← `scheduled-membership-health.yml` (hourly :17)
- [x] T2 `cron-weekly-analytics.ts` ← `scheduled-weekly-analytics.yml` (Mon 06:00) **— AFTER C2, C4, C5.** Cascade converted to `inngest.send()`.
- [x] T3 `cron-ruleset-bypass-audit.ts` ← `scheduled-ruleset-bypass-audit.yml` (daily 06:13). GH App auth.
- [x] T4 `cron-gh-pages-cert-state.ts` ← `scheduled-gh-pages-cert-state.yml` (daily 03:00). Tighten Sentry margin 240→30.
- [x] T5 `cron-cloud-task-heartbeat.ts` ← `scheduled-cloud-task-heartbeat.yml` (daily 09:30)
- [x] T6 `cron-content-publisher.ts` ← `scheduled-content-publisher.yml` (daily 14:00). 12 social API secrets via `buildPublisherEnv()`.
- [x] T7 `cron-content-vendor-drift.ts` ← `scheduled-content-vendor-drift.yml` (Mon 11:17). Bot-PR with synthetic checks.
- [x] T8 `cron-linkedin-token-check.ts` ← `scheduled-linkedin-token-check.yml` (Mon 11:00, staggered from 09:00)
- [x] T9 `cron-nag-4216-readiness.ts` ← `scheduled-nag-4216-readiness.yml` (Mon 14:00)
- [x] T10 `event-cf-token-expiry-check.ts` ← `scheduled-cf-token-expiry-check.yml` (manual dispatch). No Sentry cron monitor.
- [x] T11 `cron-plausible-goals.ts` ← `scheduled-plausible-goals.yml` (monthly 1st 07:00)
- [x] T12 `cron-rule-prune.ts` ← `scheduled-rule-prune.yml` (quarterly). Bot-PR with synthetic checks.
- [x] T13 `cron-skill-freshness.ts` ← `scheduled-skill-freshness.yml` (monthly 1st 02:00)

## 5. Cleanup

- [x] 5.1 Verify `ls .github/workflows/scheduled-*.yml | wc -l` returns exactly 4 ✓
- [x] 5.2 GHA secret audit: 16 orphaned secrets identified, pruning issue filed as #4488
- [x] 5.3 File follow-up issue: KPI-miss alerting replacement → #4489
- [x] 5.4 Update #3948 issue body with completion status
- [ ] 5.5 Run `/soleur:compound` to capture Phase 2 learnings

## Dependencies

```
#4472 ──→ C1, C2, C3, C4, C5
C2, C4, C5 ──→ T2 (cascade targets must be on Inngest before dispatcher)
```

Everything else is independent.
