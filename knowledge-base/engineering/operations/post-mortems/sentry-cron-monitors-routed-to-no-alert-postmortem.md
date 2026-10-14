---
title: "Every Sentry cron-monitor failure opened an issue that emailed nobody — 59 detectors bound to no alert workflow"
date: 2026-09-24
incident_pr: 8694
incident_window: "Latent from the monitors' creation until the PR #8694 apply. Exact start unmeasured: every cron detector read `workflowIds: []` when first measured on 2026-09-23. Observed consequences inside the window: `scheduled-content-generator` erroring since at least 2026-08-25, `scheduled-follow-through` since at least 2026-08-27, `scheduled-legal-audit` last checked in 2026-06-10, and five monitors muted."
recovery_at: "The first apply-sentry-infra.yml push run after PR #8694 merges (creates sentry_alert.cron_monitor_failure bound to all 59 detectors); proof of a live fire is AC16 of the plan."
suspected_change: "Structural, not a regression: the cron monitors were declared in Terraform with no alert bound to their detectors, and the IaC alert rules bind only the project issue-stream detector (1213799). A cron failure therefore opened a Sentry issue whose detector had no workflow, so no email route fired."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - observability (Sentry cron monitors: 59 detectors routed to no alert workflow)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: observability only. No personal data was accessed, altered, lost or
# disclosed; the failure was a missing alert route. Art. 33/34 do not trigger. Recorded explicitly
# rather than left blank so the evaluation is on the record.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Sentry cron monitors open an issue on a missed or failed check-in. None of the 59 cron detectors
was bound to an alert workflow, so those issues emailed nobody. Scheduled jobs failed for weeks
without the operator hearing about it, and five of the monitors were muted.

## Status

resolved — the route ships in PR #8694; the unmute of the muted monitors is tracked in #8704.

## Symptom

A red cron monitor produced no email. Measured while planning #8505 (alerting on Anthropic credit
exhaustion): every cron detector read `workflowIds: []`, so red monitors had paged no one.

## Incident Timeline

- **Start time (detected):** 2026-09-23
- **End time (recovered):** first `apply-sentry-infra.yml` push run after PR #8694 merges
- **Duration (MTTR):** about one day from detection to the fix PR

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-23 | While planning #8505, measured every cron detector as `workflowIds: []`; filed #8630. |
| agent | 2026-09-24 | Measured that the pinned provider (0.15.7) can bind cron detectors via `sentry_alert.monitor_ids`; confirmed on a live cron event that the occurrence carries the monitor's detector id. |
| agent | 2026-09-24 | Recorded the measurement, the red-monitor backlog and the muted-monitor decisions on #8630; filed #8704 for the unmute. |
| agent | 2026-09-24 | Opened PR #8694: one email workflow bound to all 59 detectors, three guards, audit and doc corrections. |

## Participants and Systems Involved

Sentry (cron monitors, workflow engine), the `apps/web-platform/infra/sentry` Terraform root and
`apply-sentry-infra.yml`, the Inngest and GitHub Actions cron emitters, the operator mailbox.

## Detection (+ MTTD)

- **How detected:** manual, while planning an adjacent alert (#8505). No monitoring
  detected it: the monitoring was the thing that was not wired.
- **MTTD (mean time to detect):** unmeasured; at least weeks (the oldest affected monitor's last
  check-in is 2026-06-10).

## Triggered by

system — a configuration gap present since the monitors were declared.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Cron detectors are bound to no workflow | `GET detectors/<id>/` returns `workflowIds: []` for every cron detector; a live cron event's detector (1493363) had none | — | confirmed |
| The IaC alert rules could still catch cron issues through the issue-stream detector | — | All 33 IaC rules bind the issue-stream detector (1213799) only; a cron issue's detector is the monitor's own | rejected |

## Resolution

PR #8694 adds `sentry_alert.cron_monitor_failure` (first-seen / reappeared / regression, at most one
email per monitor per day, `issue_owners` → `ActiveMembers`) bound to every declared cron detector,
plus guards so a new monitor cannot be left unrouted silently.

## Recovery verification

After the apply: the post-apply fidelity probe must compare the live `cron-monitor-failure`
workflow field-for-field with `alert-reference.json` (59 `detectorIds`), and the workflow's
`lastTriggered` must advance for a named failing monitor within 24 h (plan AC16).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did a red cron monitor send no email? Its issue belonged to a detector with no workflow.
2. Why no workflow? The IaC alert rules bind only the project issue-stream detector, and no rule
   was ever written for the cron detectors.
3. Why was none written? The provider's cron-monitor resource has no alert attribute, so it looked
   as if the link could not be expressed; the link lives on the alert side (`monitor_ids`).
4. Why did nothing notice for weeks? The audit's Class A counted unrouted detectors but treated
   "all unrouted" as the normal state, and no check read whether an alert ever fired.
5. Why will some failures stay silent even after the route ships? Five monitors are muted per
   monitor environment, the provider cannot express mute, and a muted monitor sends nothing; the
   unmute is a tracked operator write (#8704).

## Versions of Components

- **Version(s) that triggered the outage:** every version since the cron monitors were declared.
- **Version(s) that restored the service:** the PR #8694 merge commit.

## Impact details

### Services Impacted

Scheduled jobs whose failures went unreported, among them `scheduled-content-generator`,
`scheduled-follow-through`, `scheduled-legal-audit` and the Inngest/queue health watchdogs.

### Customer Impact (by role)

- Prospect: none directly; the content pipeline stall (#8145) delayed published content.
- Authenticated app user: none directly observed; a failing watchdog on a user surface would not have paged.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None measured.

### Team Impact

The operator believed red monitors paged; runbooks said so. Failures were found only by manual
investigation.

## Lessons Learned

### Where we got lucky

The gap surfaced while planning an adjacent alert (#8505) rather than after a user-visible failure.

### What went well

The measurement came first: the provider was checked at the exact pin, and hop 2 was confirmed
on a live event before anything was built on it.

### What went wrong

A "pages" claim was written into runbooks without a check that the route existed, and a count
of unrouted detectors was read as healthy because it had always been the total.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8704 | Unmute the three recovered monitors now and the two still failing once their next check-in is ok (mute is not provider-expressible). | open |
| #8495 | Fix the GitHub-cron cadence of the two watchdogs that miss most check-ins (they stay routed as the route's canary until then). | open |
| #8145 | Content-generator publishing stall behind one of the long-red monitors. | open |
| #6590 | Prune cron monitors whose silence is detectable elsewhere, including the long-dead ones in the red backlog on #8630. | open |
