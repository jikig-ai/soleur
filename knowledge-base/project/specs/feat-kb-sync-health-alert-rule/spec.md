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
- NG4: ~~No alert on the cron's internal scan-failure ops~~ **[Reversed
  2026-06-03 per plan-review]** — feature-only matching (FR2) now DOES alert on
  the probe-failure ops. Plan-review showed arms 2/3 swallow their scan errors
  and the heartbeat misses them, so the probe-failure ops are the only
  broken-probe signal; excluding them reintroduced the silent-failure class the
  PIR targets. These failures are rare, so they do not cause fatigue (lifecycle
  conditions handle finding-repeat fatigue).

## Functional Requirements

- FR1: Add a `sentry_issue_alert "workspace_sync_health"` resource to
  `apps/web-platform/infra/sentry/issue-alerts.tf`, mirroring the structure of
  `chat_message_save_failure` (`issue-alerts.tf:349-396`).
- FR2: `filters_v2` MUST match `feature EQUAL "workspace-sync-health"` ONLY (no
  `op` filter). Every event the cron emits on this feature is operator-actionable
  — the 3 findings (`ready-null-installation`/`stale-sync-failed`/`went-quiet`)
  AND the 4 probe-failure ops (`scan`/`scan-stale`/`scan-went-quiet`/`went-quiet-probe`),
  which are the only signal when arms 2/3 swallow a scan error the heartbeat
  misses. Feature-only matching covers all of them and future-proofs against new
  cron arms. [Updated 2026-06-03 per plan-review: was `op IS_IN {3 finding ops}`.]
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
  `apps/web-platform/test/sentry-chat-alert-op-contract.test.ts` that asserts the
  `feature` tag (`workspace-sync-health`) appears in BOTH the cron's
  `SENTRY_FEATURE` const and the alert's feature filter, so a rename on either
  side breaks the test rather than silently un-matching the alert (G3). Under
  feature-only matching there is no op-set to pin.
- TR2: The change is Terraform-only under `apps/web-platform/infra/sentry/`;
  applied via the existing `apply-sentry-infra.yml` workflow. No migration, no
  app deploy.
- TR3: `terraform fmt` + `terraform validate` clean for the sentry root.

## Acceptance Criteria

- AC1: `terraform plan` shows exactly one new `sentry_issue_alert` resource and
  no diffs to existing rules.
- AC2: The contract test (TR1) passes and fails if the `feature` tag is renamed
  in the cron without updating the alert (or vice versa).
- AC3: The alert's `filters_v2` contains exactly one filter — `feature EQUAL
  "workspace-sync-health"` — and no `op` filter.
