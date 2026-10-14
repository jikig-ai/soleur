---
date: 2026-06-03
topic: kb-sync-health-alert-rule
issue: 4882
branch: feat-kb-sync-health-alert-rule
pr: 4885
lane: single-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Sentry alert rule for workspace-sync-health findings (#4882)

## What We're Building

A single `sentry_issue_alert "workspace_sync_health"` Terraform resource in
`apps/web-platform/infra/sentry/issue-alerts.tf` that notifies the operator
when the existing `cron-workspace-sync-health` daily probe reports a workspace
whose KB clone is diverged, stale, or unreachable.

**No application-code change.** The detection signal already exists; this closes
the *notification* half of the KB-sync-stale PIR (PR #4878 closed recovery; the
probe arms #4712/#4717 closed detection-signal; this closes alerting).

## Premise Correction (load-bearing)

Issue #4882 was filed 2026-06-03 13:38 UTC as a PIR follow-up asserting
"detection still depends on a user noticing a missing file" and proposing a new
"liveness/age alert (Sentry rule or scheduled probe)." That premise was already
stale at filing:

- **The scheduled probe exists.** `cron-workspace-sync-health.ts` runs daily
  (`23 6 * * *`) with three arms, all merged **2026-06-01** (two days before
  #4882):
  - Arm 1: `repo_status='ready'` + `github_installation_id IS NULL`
    (unreachable by reconcile) → `op=ready-null-installation`.
  - **Arm 2 (#4712):** latest `kb_sync_history` row is `ok:false` on an
    installed workspace → `op=stale-sync-failed`.
  - Arm 3 (#4717): went-quiet (default-branch commits never synced) →
    `op=went-quiet`.
- **Both conditions #4882 proposes already emit Sentry events.** The bullet-1
  case — `non_fast_forward` with `recovered != true` (un-pushed local commits,
  self-heal could NOT fix) — writes a `{ok:false, error_class:'non_fast_forward'}`
  row (verified at `kb-route-helpers.ts:307-309` + `workspace-reconcile-on-push.ts`
  success path `{ok:true, recovered}` vs failure path `{ok:false, error_class}`).
  Arm 2 fires on *any* `latest.ok === false`, so it already catches this. The
  bullet-2 case (`ok:false` latest) *is* Arm 2.
- **The genuine gap:** `issue-alerts.tf` has rules for auth bursts, BYOK
  breaches, and `chat_message_save_failure` — but **none for
  `feature=workspace-sync-health`**. The cron's `reportSilentFallback` events
  land in Sentry un-notified. This is the `hr-no-dashboard-eyeball-pull-data-yourself`
  failure mode: signal exists, notification doesn't.

Scope was confirmed with the operator: **alert-rule only.**

## Why This Approach

Mirror the existing `chat_message_save_failure` rule (`issue-alerts.tf:349-396`),
which already solved the identical problem class (page the solo founder on a
single-user-incident-class silent failure) and encodes the anti-fatigue design
in its comments. Reusing the proven pattern is lower-risk than inventing alert
config, and keeps the op/feature contract test pattern
(`sentry-chat-alert-op-contract.test.ts`) consistent.

### Alert-fatigue mitigation (operator's primary concern)

The operator flagged alert fatigue as the worst outcome: a rule that fires on
every daily cron run while one workspace is transiently `ok:false` → operator
mutes the channel → a real `non_fast_forward` divergence gets ignored.

The `chat_message_save_failure` pattern already mitigates this **by design**:
`action_match="any"` with lifecycle conditions `first_seen_event` /
`reappeared_event` / `regression_event` (NOT a per-event condition). Sentry
folds repeated daily fires of the same workspace into **one issue** by
fingerprint, so the rule pages on the *new* occurrence and on *regression after
the operator resolves it* — not on every daily re-fire. `frequency` is the
re-notification throttle (minutes) and must be a value not already taken by a
sibling rule (taken: 5, 10, 15, 30, 60, 61, 62) to avoid Sentry POST-time
exact-duplicate dedup.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Alert-rule only; no app-code change | Probe + signal already shipped (#4712/#4717); only notification is missing |
| 2 | Mirror `chat_message_save_failure` resource | Proven same-class pattern; encodes anti-fatigue lifecycle-condition design |
| 3 | Match `feature=workspace-sync-health` only (no `op` filter) **[Updated 2026-06-03 at plan-review]** | Originally scoped to 3 finding ops to minimize fatigue, but plan-review found arms 2/3 swallow scan errors the heartbeat misses, so the probe-failure ops are the only broken-probe signal. Feature-only covers findings + probe-failures, is future-proof, and the dedicated feature tag means every event is operator-actionable. Fatigue is handled by lifecycle conditions, not op-scoping. |
| 4 | Lifecycle conditions (first_seen/reappeared/regression), not per-event | Folds persistent daily re-fires into one issue; pages on new + regression only |
| 5 | `frequency` = unused distinct value (e.g. 11 or 20) | Avoid Sentry exact-dup dedup vs sibling rules (5/10/15/30/60/61/62 taken) |
| 6 | `notify_email` IssueOwners → ActiveMembers fallthrough | Solo-founder N=1; mirrors `chat_message_save_failure`; events carry no cross-tenant content (op + hashed userId only) |
| 7 | Pin op/feature contract with a test | Mirror `sentry-chat-alert-op-contract.test.ts` so a future op-string rename in the cron can't silently un-match the alert |

## Open Questions

- **frequency value:** pick 11 or 20 (both unused). Plan-time detail.
- **`error_class` differentiation (deferred):** #4882 bullet-1 wants the
  un-self-healable `non_fast_forward` case (operator must manually intervene)
  alerted *more loudly* than transient `sync_failed`. Arm 2 currently lumps
  both into `stale-sync-failed`. A distinct op/severity for the
  `error_class=non_fast_forward AND recovered!=true` sub-case is a cron-side
  refinement, explicitly out of the confirmed alert-rule-only scope. Defer.
- **`age threshold` (deferred):** #4882 bullet-2 wants "older than N hours."
  The lifecycle-condition design makes age largely moot (one issue per
  divergence, re-paged on regression). Defer unless the alert proves too eager.
- **scan-failure ops (deferred follow-up):** alerting on the cron's own
  `scan`/`scan-stale`/`scan-went-quiet`/`went-quiet-probe` failure ops would
  catch the *monitor itself* breaking. Arguably covered by the cron heartbeat;
  excluded here to honor the fatigue concern. Candidate follow-up issue.

## Domain Assessments

**Assessed:** Engineering (single-domain lane; observability config change).
No leaders spawned — the design is fully determined by the existing
`chat_message_save_failure` pattern and the cron's verified emitted event tags;
a leader spawn would re-derive the pattern's own comments. `USER_BRAND_CRITICAL`
= false: read-only operator-notification config, no credential/data/billing/
dev-prd surface (the "Alert fatigue" framing carries no brand-critical vector).

## User-Brand Impact

- **Artifact:** the new `sentry_issue_alert` rule.
- **Vector:** misconfiguration → either (a) rule conditions don't match the
  cron's actual `feature`/`op` tags, so events stay un-notified and the PIR
  failure mode (user reports stale KB before operator is alerted) recurs; or
  (b) rule too broad → alert fatigue → operator mutes → real divergence ignored.
- **Threshold:** single-user incident (inherited from the source PIR).
- **Mitigation:** op/feature contract test (Decision 7) closes (a);
  lifecycle-condition design + scoped finding-ops (Decisions 3-4) close (b).
