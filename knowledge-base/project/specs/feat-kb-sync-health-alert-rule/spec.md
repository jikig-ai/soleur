---
feature: kb-sync-health-alert-rule
issue: 4882
branch: feat-kb-sync-health-alert-rule
pr: 4885
lane: single-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-06-03
---

# Spec: Sentry alert rule for workspace-sync-health findings

## Problem Statement

The `cron-workspace-sync-health` daily probe (arms merged #4712/#4717,
2026-06-01) reports diverged/stale/unreachable workspace KB clones to Sentry via
`reportSilentFallback` with `feature=workspace-sync-health`. But
`apps/web-platform/infra/sentry/issue-alerts.tf` has **no alert rule** matching
that feature, so the events sit in Sentry un-notified — the operator only learns
of a broken KB sync when a user reports a missing file (the exact failure mode
of the 2026-06-03 KB-sync-stale PIR). #4878 closed recovery; the probe closed
detection-signal; this closes alerting.

## Goals

- G1: Notify the operator when `cron-workspace-sync-health` reports a
  user-actionable finding (diverged, stale, or unreachable workspace KB clone).
- G2: Do so without alert fatigue — a persistent finding pages once, not on
  every daily cron re-fire.
- G3: Pin the op/feature contract so a future cron op-string rename cannot
  silently un-match the alert.

## Non-Goals

- NG1: No application-code change. The cron and its three detection arms already
  exist and emit the events.
- NG2: No `error_class`-aware severity differentiation for the un-self-healable
  `non_fast_forward` case (deferred — cron-side refinement, out of scope).
- NG3: No explicit "older than N hours" age gate (deferred — lifecycle-condition
  design makes it largely moot).
- NG4: No alert on the cron's internal scan-failure ops
  (`scan`/`scan-stale`/`scan-went-quiet`/`went-quiet-probe`) — deferred
  follow-up; excluded to honor the alert-fatigue constraint.

## Functional Requirements

- FR1: Add a `sentry_issue_alert "workspace_sync_health"` resource to
  `apps/web-platform/infra/sentry/issue-alerts.tf`, mirroring the structure of
  `chat_message_save_failure` (`issue-alerts.tf:349-396`).
- FR2: `filters_v2` MUST match `feature EQUAL "workspace-sync-health"` AND
  `op IS_IN "ready-null-installation,stale-sync-failed,went-quiet"`
  (`filter_match="all"`). These are the three user-actionable finding ops emitted
  by the cron (Arm 1 / Arm 2 / Arm 3 respectively).
- FR3: `conditions_v2` MUST use the lifecycle triad `first_seen_event` /
  `reappeared_event` / `regression_event` with `action_match="any"` (the
  anti-fatigue design: one issue per divergence, re-page on regression only —
  NOT a per-event condition).
- FR4: `frequency` MUST be a value not already used by a sibling rule
  (taken: 5, 10, 15, 30, 60, 61, 62) to avoid Sentry POST-time exact-duplicate
  dedup. Use 11 or 20.
- FR5: `actions_v2` MUST be `notify_email` with `target_type="IssueOwners"`,
  `fallthrough_type="ActiveMembers"` (solo-founder N=1, mirrors siblings; events
  carry only `op` + hashed `userId`, no cross-tenant content).
- FR6: Add a `lifecycle { ignore_changes = [environment] }` block, matching
  sibling rules.

## Technical Requirements

- TR1: Add a contract test mirroring
  `apps/web-platform/test/sentry-chat-alert-op-contract.test.ts` that asserts
  the alert rule's matched op strings are exactly the set of finding-op strings
  emitted by `cron-workspace-sync-health.ts`, so a cron op rename breaks the
  test rather than silently un-matching the alert (G3).
- TR2: The change is Terraform-only under `apps/web-platform/infra/sentry/`;
  applied via the existing `apply-sentry-infra.yml` workflow. No migration, no
  app deploy.
- TR3: `terraform fmt` + `terraform validate` clean for the sentry root.

## Acceptance Criteria

- AC1: `terraform plan` shows exactly one new `sentry_issue_alert` resource and
  no diffs to existing rules.
- AC2: The contract test (TR1) passes and fails if any of the three finding-op
  strings is changed in the cron without updating the alert.
- AC3: The matched op set equals `{ready-null-installation, stale-sync-failed,
  went-quiet}` and `feature` equals `workspace-sync-health`.
