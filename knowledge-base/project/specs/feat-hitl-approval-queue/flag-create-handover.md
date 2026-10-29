# `approval-queue` flag: creation hand-over (not done by the PR)

The PR registers the flag in code only (`lib/feature-flags/server.ts` RUNTIME_FLAGS, `.env.example` `FLAG_APPROVAL_QUEUE=0`, `flip.sh` map). Nothing is created in Flagsmith or Doppler and nothing is flipped. Absent means OFF, so the merge does not depend on it.

## Operator steps (typed-yes, each a production write; run only after the legal commit and the post-merge checks below are green)

1. Create the feature with `soleur:flag-create` (name `approval-queue`, default OFF, mirror `FLAG_APPROVAL_QUEUE=0` in Doppler dev and prd).
2. Do NOT flip it as part of the create. Enabling is a separate decision per workspace cohort via a per-workspace segment override (`soleur:flag-set-role`), evaluated per workspace identity.

## Preconditions before anyone enables it

- Migration 180 applied in prd (release workflow `verify-migrations` green) and the cron monitor `cron-approval-expiry` checking in (Sentry).
- ADR-307 adopted; the legal records in this PR merged.
- Evidence gates #9776 and #10111 closed before the ask path is described as measured.
- Autonomous-mode (`workspace_set_autonomous`) card copy still PROVISIONAL: needs CPO and CLO sign-off before the first workspace is enabled.
- Cron monitor routing: `scheduled_approval_expiry` is declared-unrouted under the two-PR rule (`cron_monitor_alert_unrouted` in `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`) and has no independent cover (no Better Stack missing-`SOLEUR_APPROVAL_SWEEP` monitor exists, and `gate_unanswered` is emitted by the sweep itself, so a dead sweep emits nothing). Before the flag is turned on for anyone: after the monitor's first measured check-in, route it by adding `sentry_cron_monitor.scheduled_approval_expiry.id` to the sorted `monitor_ids` of `sentry_alert.cron_monitor_failure` and deleting its unrouted entry, in a follow-up PR (read-only check afterwards: the monitor shows `ok` check-ins in Sentry).
