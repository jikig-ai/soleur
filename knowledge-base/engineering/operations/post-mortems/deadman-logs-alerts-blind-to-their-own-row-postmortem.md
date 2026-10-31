---
title: "Postmortem: the luks host-timer and cost-capture dead-man logs alerts could not see their own once-a-day row, so they paged on nothing and would not have paged on a real fault"
date: 2026-10-31
incident_pr: 11653
incident_window: "2026-09-27 (first nightly passing luks row the alert could not see) → 2026-10-30 (triaged: host healthy, alerts structurally blind)"
recovery_at: "unresolved — heartbeats born paused by PR 11653; arming and the two Better Stack incident resolves are owner-gated, tracked on #11631"
suspected_change: "Design defect from creation: two native Better Stack logs alerts evaluated a 26 h and a 24 h window, but the evaluator only reads the hot window (about 1 h measured on 2026-10-30), and the row they match is written once a day. Not a regression from a specific change."
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - dead-man alert
  - host timer dark
  - claude cost capture dark
  - logs alert hot window
  - stuck Better Stack incident
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — monitoring-design incident, no personal data exposed or accessed"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Two native Better Stack logs alerts, `luks_monitor_host_timer_dark` and `claude_cost_capture_dark`, existed to page when web-1's once-a-day `luks-monitor.service` row, or the Anthropic cost markers, stopped arriving. Both opened incidents (mirrored as #11048 and #11049) that stayed open. Triage on 2026-10-30, read-only, showed web-1 healthy (39 nightly passing rows from 2026-09-27 to 2026-10-30, three green verify runs) and the alerts structurally blind: they evaluated a long window against an evaluator that sees about one hour, so the alert read `Current value: 0` every night while the row existed in the archive.

## Status

ongoing — the old alerts are replaced by PR 11653, but the replacement heartbeats are born paused, so there is no paging dead-man for these two signals until the owner arms them (deadline 2026-11-13). The two Better Stack incidents also still need the owner's explicit resolve.

## Symptom

An open incident on a healthy host (a false page), and, by the same mechanism, no page if the host timer had really gone dark.

## Incident Timeline

- **Start time (detected):** 2026-10-30, triage of #11048 and #11049
- **End time (recovered):** not yet, see Status
- **Duration (MTTR):** n/a, ongoing

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-10-30 | Incident detected: open Better Stack incidents on a healthy host. |
| agent | 2026-10-30 | Read-only triage: 39 nightly passing rows, verify runs green; #11048 classified as a monitor-design defect, #11631 filed. |
| agent | 2026-10-30 | Phase 0 live measurement: the feeder's SQL matches the archive for both targets (`n=1`, `n=4`); hot window about 1 h. |
| agent | 2026-10-31 | PR 11653 opened: heartbeats fed hourly from hot plus archive, born paused. |

## Participants and Systems Involved

Better Stack Logs (native logs alerts, hot window plus archive), Better Stack Uptime heartbeats, the Vector shipper on web-1, `luks-monitor.service`, the Inngest cost markers, GitHub Actions (the new hourly feeder), Sentry cron monitors.

## Detection (+ MTTD)

- **How detected:** a person reading the open incident mirrors during a LUKS posture review, not by the monitor that was meant to detect it.
- **MTTD (mean time to detect):** about 33 nights from the first row the alert could not see.

## Triggered by

system — a design defect in the alert's evaluation window.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The alert window is longer than what the evaluator can read | Measured hot window about 1 h; the matching row exists in the archive (`n=1`) while the alert read 0 | None found | confirmed |
| The host timer or the shipper really was dark | — | 39 nightly passing rows in the archive; verify runs green | rejected |

## Resolution

Replace both alerts with Better Stack heartbeats fed hourly by a scheduled workflow that reads hot plus archive and beats only when a qualifying row exists in the old window (PR 11653). A sentinel bans any logs alert whose query period exceeds 900 s so the shape cannot return. The heartbeats are born paused; arming and the incident resolves follow the runbook section "Arming the dead-man heartbeats (#11631)".

## Recovery verification

Not yet complete. Live positive control passed before the change (`n=1` and `n=4` over the real windows); post-apply feeder runs showing `qualifying_row_heartbeat_paused` and the owner's arm read-back are the remaining proof.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the incident stay open on a healthy host? The alert never saw the row it was watching for.
2. Why not? Its 26 h / 24 h window exceeds the hot window the evaluator reads, and the row arrives once a day.
3. Why was that not caught at creation? The alert's test proved the query shape, not that the evaluator could see the row; the vendor does not expose the evaluated value over the read-only API.
4. Why did it run for 33 nights? Nothing watched the watcher, and the incident mirror only creates issues.
5. Why does it matter beyond a false page? The same blindness would have hidden a real dark host timer, so the dead-man was not a dead-man.

## Versions of Components

- **Version(s) that triggered the outage:** n/a (design defect since creation)
- **Version(s) that restored the service:** PR 11653 (pending merge and arming)

## Impact details

### Services Impacted

LUKS host-timer liveness signal for web-1 and the Anthropic cost-capture liveness signal. No customer-facing service was degraded.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None measured.

### Team Impact

Two stuck incidents and a misleading "dark" signal consumed triage time on 2026-10-30.

## Lessons Learned

### Where we got lucky

The host and the shipper were healthy throughout, so the blind alerts hid nothing real.

### What went well

Read-only triage found the cause from existing data; the Phase 0 live control proved the replacement predicate against the real archive before any change.

### What went wrong

A dead-man alert was accepted without proving its evaluator could see the row it matches. The hot-window limit was inferred, not observed (still unobservable via the read-only API). Until the owner arms the heartbeats, the replacement leaves a window with no paging dead-man.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #11631 | Arm the two heartbeats (read-back), resolve the two Better Stack incidents, then drop `arming_pending` (deadline 2026-11-13) | open |
| #11671 | Measure whether `claude_cost_daily_burn` (24 h sum) shares the same hot-window blind spot | open |
| #11672 | After the first green apply: remove the retained destroy targets and census rows, route the Sentry monitor, extract shared heartbeat plumbing | open |
| #11670 | Move the feeder secrets into a branch-restricted GitHub Environment | open |
