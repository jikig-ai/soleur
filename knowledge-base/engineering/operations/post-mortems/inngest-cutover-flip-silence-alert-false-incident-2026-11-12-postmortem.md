---
title: "Inngest cutover-flip silence alert false incident 2026-11-12"
date: 2026-11-18
incident_pr: 12865
incident_window: "2026-11-12T23:45:00Z → TBD"
recovery_at: "TBD"
suspected_change: "PR #12709 (re-arm of the inngest_cutover_flip_silent Logs alert, applied 2026-11-13T00:01:47Z by run 43333522781)"
brand_survival_threshold: none
status: open
triggers:
  []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach (alert over operator telemetry; data_categories_breached empty, risk_to_subjects none)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The Better Stack Logs alert `soleur-inngest-cutover-flip-silent-prd` opened incident 1051496324 on healthy data and has held it open since. Nothing went silent. The vendor evaluator reads `Current value: 0` for this `lower_than 1` row-count alert while 11 to 12 matching rows arrive every hour.

## Status

open — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth. It becomes `resolved` when the inverted alert (PR #12865) is live with rows arriving and the owner has resolved incident 1051496324 (tracked in #12878).

## Symptom

Incident 1051496324 has been open since 2026-11-12T23:45:00Z (start time as Better Stack recorded it). Its metadata reads `Current value: 0`, `Operator: lower_than`, `Threshold value: 1`. Its GitHub mirror, #12726, a P1 action-required issue, collected a "Still open" comment every 15 minutes, about 460 of them.

## Incident Timeline

- **Start time (detected):** 2026-11-12T23:45:00Z
- **End time (recovered):** TBD
- **Duration (MTTR):** TBD (status not resolved)

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-11-13T00:01:47Z | Re-arm apply (run 43333522781) modified `logtail_exploration_alert.inngest_cutover_flip_silent`; before that the alert was paused. |
| agent | 2026-11-12T23:45:00Z | Incident 1051496324 opened at the first evaluation after the un-pause, back-dated to this time. |
| agent | 2026-11-17T15:50:00Z | Read-only diagnosis: object rows 11 to 12 per hour, no hour missing; largest gap 370 s against a 900 s window; the alert's own SQL replayed on four windows returned 3, 2, 2, 3. |
| agent | 2026-11-18 | PR #12865 opened: inverts the alert to the ADR-218 missing-count form (`higher_than 0`) and adds a throwaway canary. Merge waits for the owner's typed go. |

## Participants and Systems Involved

Operator (single founder); Claude Code agents. Systems: Better Stack Logs (alert evaluator, source 2457081), Better Stack Uptime incidents, the Inngest production host's cutover-flip unit and Vector shipper, the GitHub incident mirror.

## Detection (+ MTTD)

- **How detected:** monitoring — monitoring system vs. external/manual report. The alert itself opened the incident; the diagnosis that it was false came from a read-only replay of its SQL.
- **MTTD (mean time to detect):** 0h0m (the incident is the monitor's own output; the false-positive finding took about 4.7 days).

## Triggered by

provider — one of user / system / market movement / provider. The vendor's Logs evaluator reads 0 on `lower_than` silence alerts on this account.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The flip unit went silent | none | 11 to 12 object rows per hour throughout; max gap 370 s | rejected |
| The evaluator reads 0 on `lower_than` silence alerts | the alert SQL replays to 2 to 3 on the same windows; at least four `lower_than` alerts on this account read 0 on healthy data; the inverted egress and relay alerts opened no false incident since 2026-11-06 | none measured | accepted (pattern, vendor-side mechanism not observed) |

## Resolution

PR #12865 inverts the alert to the ADR-218 missing-count form: value `greatest(toInt64(1) - toInt64(count(DISTINCT host_name)), 0)`, paging on `higher_than 0`, `treat_as_zero` kept. A throwaway canary, identical except for a host that never emits, proves the inverted shape can deliver an incident. The owner then resolves incident 1051496324.

## Recovery verification

TBD — the apply +25 min tracker read on #12878 (alert live and unpaused at `higher_than 0`, rows arriving, canary incident present, no new production incident), then the owner's resolve of 1051496324.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was an incident open on healthy data? The alert's evaluator read `Current value: 0` while the source held 2 to 3 matching rows per window.
2. Why did that page? The alert fired on `lower_than 1`, so a false 0 is a page.
3. Why was the alert still in the `lower_than` shape? ADR-218 converted the egress and relay silence alerts to the inverted form on 2026-11-05/06, but this one was paused at the time and was re-armed in its original shape.
4. Why was the false 0 not caught at re-arm? Nothing proved the shape could deliver a correct value on this account before arming it; there was no canary.
5. Why does it matter? A permanently open false incident trains the reader to ignore it and masks a real silence, which would open no new incident.

## Versions of Components

- **Version(s) that triggered the outage:** `apps/web-platform/infra/betterstack-logs-alerts.tf` as re-armed by PR #12709 (applied 2026-11-13T00:01:47Z).
- **Version(s) that restored the service:** N/A — not yet restored (PR #12865 pending the owner's go).

## Impact details

### Services Impacted

No service was impacted. The detection surface was degraded: a real failure of the cutover-flip unit before its first emit would have opened no new incident, leaving the LUKS deadman (about 26 h) as the backstop.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none
- Authenticated app user: none (scheduled agent runs kept working)
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

Unknown / N/A

### Team Impact

About 460 automated "Still open" comments on P1 issue #12726, and one diagnosis session.

## Lessons Learned

### Where we got lucky

The flip unit did not actually fail during the five days the alert could not have reported it.

### What went well

The cause was found entirely from read-only Logs and Uptime API reads, with no SSH. The fix copies the inverted shape that has already delivered correctly for the egress and relay alerts.

### What went wrong

The alert was re-armed in a shape already known to read 0 on this account, with no canary proving it could deliver.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `No action items — incident fully resolved in the source PR with no residual work.` as a line of its own, with no emphasis — the permitted no-item form is plain so that the markdown linter (MD049, emphasis-style) cannot restyle it; the `/ship` gate accepts the plain line (and the underscore/asterisk-wrapped spellings shipped before this template changed).

| Issue | Action | Status |
|---|---|---|
| #12878 | Post-apply reads (+25 min, +4 h, +24 h), canary retirement under F2 amended, owner-go resolve of incident 1051496324 | open |
| #12190 | Heartbeat poller fallback if the canary shows the inverted shape cannot deliver | open |
| #12917 | Shared HCL lexer residual (`${ }` depth tracking) that the flip guard confines but does not fix | open |
