---
title: "Inngest dedicated-host watchdog filed hourly false P1s by reading the event log as probe rows"
date: 2026-09-27
incident_pr: 8873
incident_window: "2026-09-25T07:17Z .. merge of PR #8873"
recovery_at: "merge of PR #8873 (verified post-merge by a contaminated-window watchdog run)"
suspected_change: "substring row selection in the #7674 arm of scheduled-inngest-health.yml, exposed once issue bodies quoting the marker reached the inngest event log"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - monitoring
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — false alarm on a monitoring path; no personal data processed, exposed or lost"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The dedicated-host arm of `scheduled-inngest-health.yml` graded a healthy dedicated inngest host
`probe-unavailable` and filed a P1 pair ("Dedicated inngest host is not serving" and "No live inngest
scheduler") every hour. The host was serving throughout (`http_code=200 server_active=active`).

## Status

resolved — the fix is PR #8873; post-merge verification is recorded on that PR.

## Symptom

A new `[ci/inngest-dedicated-host]` + `[ci/inngest-no-live-scheduler]` issue pair roughly hourly,
each closed by the next healthy tick: #8823/#8824, #8829/#8830, #8833/#8834, #8850/#8851, #8862/#8863.

## Incident Timeline

- **Start time (detected):** 2026-09-25T07:17Z (first false pair, #8823)
- **End time (recovered):** merge of PR #8873
- **Duration (MTTR):** roughly two days of intermittent false alarms

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-25T07:17 | First false pair filed by the watchdog. |
| agent | 2026-09-25T10:05 | Better Stack read: 21 rows, 3 real probe rows, 15 `doppler` event-log rows quoting the marker; #8846 filed with the root cause. |
| agent | 2026-09-25 | Planning measured the full consumer set and the same blind spot in the cutover liveness counters. |
| agent | 2026-09-27 | PR #8873: every consumer selects by emitter plus anchor through one shared lib. |

## Participants and Systems Involved

`scheduled-inngest-health.yml`, Better Stack Logs, the dedicated inngest host `soleur-inngest`, and the
readers of its probe rows (dark-gate lib, cutover gates, follow-through probes, `inngest-host-state.sh`).

## Detection (+ MTTD)

- **How detected:** the watchdog's own issues; the pattern of hourly open/close pairs gave it away.
- **MTTD:** under three hours from the first false pair to the root-cause issue.

## Triggered by

system — GitHub issue webhooks about the probe are logged by the inngest server on the same host.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Event-log rows quoting the marker win `tail -1` | 15 of 18 host rows were `SYSLOG_IDENTIFIER=doppler`; the chosen row had no probe fields | none | confirmed |
| The host is down | none | probe rows read `http_code=200 server_active=active` | rejected |

## Resolution

PR #8873 selects probe rows by emitter (`SYSLOG_IDENTIFIER == "inngest-server-probe"`) plus a
start-of-message anchor in every consumer, through `scripts/lib/inngest-probe-row.sh`, and raises the
watchdog read to 500 rows.

## Recovery verification

A watchdog run dispatched after merge, over a window whose newest dedicated-host row is a `doppler`
event-log row, reads `healthy`; recorded on PR #8873.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why a false alarm? The newest row the watchdog graded was not a probe row.
2. Why was it chosen? Selection was a substring match on the marker, filtered only by host.
3. Why did a non-probe row carry the marker? The inngest event log on the same host logs webhook payloads, which quote issue bodies that name the marker.
4. Why did it self-sustain? Each filed or closed alarm issue produced a new quoting row.
5. Why was substring selection there? Seven readers each carried their own predicate; none checked the emitter, and no shared definition or census existed.

## Versions of Components

- **Version(s) that triggered the outage:** main before PR #8873
- **Version(s) that restored the service:** the merge of PR #8873

## Impact details

### Services Impacted

Monitoring only: the watchdog and the issue channel. The dedicated host and every user's crons kept running.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none (crons and reminders kept firing)
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None.

### Team Impact

Alarm fatigue: repeated P1 issues for a healthy host, and a real risk of the next true alarm being dismissed.

## Lessons Learned

### Where we got lucky

The cutover liveness counters had the same blind spot in the fail-open direction; no cutover ran during the window.

### What went well

One Better Stack read, grouped by emitter, found the cause in minutes.

### What went wrong

The substring selection had recurred for the third time in this class (#6475 before it), with no census to stop a new reader.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8874 | Add an emitter clause to the wrong-volume alert SQL in `betterstack-logs-alerts.tf` | open |
| #8875 | Repo-wide rule: every Better Stack reader selects by emitter | open |
