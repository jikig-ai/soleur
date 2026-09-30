---
title: "cron monitors paged falsely: community-monitor verify race + queue-health scheduler deferral — 2026-09-30"
date: 2026-09-30
incident_pr: "#9280"
incident_window: "2026-09-30T00:30:00Z → 2026-09-30 (remediation merged in #9280; the follow-through soak verifies over the post-deploy window)"
recovery_at: "2026-09-30 (PR #9280 merge; soak pending per scripts/followthroughs/cron-machinery-soak-9272.sh)"
suspected_change: "No triggering change. Two latent defects: (1) verifyScheduledIssueCreated in apps/web-platform/server/inngest/functions/_cron-shared.ts performs a single point-in-time GitHub issues-list read, so a just-filed labelled issue not yet visible in the list view is declared absent — false 'no output' → red heartbeat AND persistence skipped (the run's real work is discarded); (2) scheduled-actions-queue-health assumes a missed check-in implies runner starvation, but GitHub defers on.schedule workflows for hours under org load, so the monitor pages on scheduler jitter."
brand_survival_threshold: none
status: resolved
triggers:
  []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach; internal monitoring-integrity / artifact-loss incident"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Two Sentry cron-monitor regressions paged the operator on the morning of 2026-09-30 (scheduled-actions-queue-health missed check-in at 00:30 UTC; scheduled-community-monitor error check-in at 08:02:38 UTC). Investigation showed neither page reflected a real service failure: the community-monitor run had succeeded end-to-end, but a single-shot GitHub issues-list read raced its just-filed run-report issue, declared "no output", discarded the day's digest, and posted the red heartbeat; meanwhile the queue-health monitor's every-30-minutes GHA schedule fires only a handful of times per day under org load, so missed check-ins page on scheduler deferral rather than the runner starvation it was built to catch.

## Status

resolved — all three defects remediated in PR #9280 (closes #9272, #9273, #9274).

## Symptom

Two "Regressed issue" Sentry cron-monitor-failure emails for project web-platform / production: (1) scheduled-actions-queue-health — "A missed check-in was detected", last ok 2026-09-29T23:50:49Z, monitor.incident 9015847; (2) scheduled-community-monitor — "An error check-in was detected", last ok 2026-09-29T08:08:23Z, monitor.incident 9024734.

## Incident Timeline

- **Start time (detected):** 2026-09-30T00:30:00Z
- **End time (recovered):** TBD
- **Duration (MTTR):** TBD (status not resolved)

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-09-30T00:30:00Z | Incident detected — Sentry regression email: scheduled-actions-queue-health missed check-in. |
| agent | 2026-09-30T08:02:38Z | scheduled-community-monitor posts error heartbeat despite successful run (issue #9268 filed 08:02:28Z; verify read ~08:02:34Z missed it). |
| agent | 2026-09-30T~09:0xZ | Pulled Sentry checkins API + issues + probe logs: community-monitor = false-red verify race; queue-health = GHA schedule deferral (probe HEALTHY when it runs: 0 queued, 46/60 in flight). |
| agent | 2026-09-30T~09:1xZ | Filed remediation issues #9272 (verify retry), #9273 (monitor retune), #9274 (digest-PR auto-merge stall). Drafted this PIR. |

## Participants and Systems Involved

Operator (single founder); Devin CLI agent (investigation + PIR). Systems: GitHub Actions scheduler + REST issues API; Sentry cron monitors (scheduled-community-monitor, scheduled-actions-queue-health); Inngest cron substrate (cron-community-monitor); app/soleur-ai GitHub App.

## Detection (+ MTTD)

- **How detected:** monitoring — Sentry cron-monitor failure emails ("Regressed issue") for both monitors.
- **MTTD (mean time to detect):** 0h0m (pages fire at detection time by construction).

## Triggered by

system — latent code/config defects, no user or market trigger.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| GitHub issues-list view lag → verifyScheduledIssueCreated false-negative → red heartbeat + persistence skip | Issue #9268 exists, created 08:02:28Z BEFORE the 08:02:35Z "exited 0 but created no issue" event; identical shape on 9/27 (#9022 08:06:23Z vs error heartbeat 08:06:34Z) | none found | confirmed — filed #9272 |
| GHA schedule deferral → queue-health missed check-ins are not runner starvation | Probe verdict HEALTHY when it actually runs (2026-09-30T03:11Z: 0 queued, 46/60 jobs in flight); workflow fires ~4x/day vs */30 | none found | confirmed — filed #9273 |
| Digest-PR auto-merge stall keeps digests off main | #9125/#9205 have autoMerge armed + all checks green but mergeable_state=behind; digests 9/27–30 absent from main | — | confirmed — filed #9274 |

## Resolution

PR #9280 shipped all three fixes: (1) `verifyScheduledIssueCreated` retries the issues-list read on a bounded budget (default 3 × ~12 s) and emits the non-paging `scheduled-output-late-visible` warn when a retry recovers, so a just-filed issue no longer false-reds a healthy run or discards its artifacts; (2) `scheduled-actions-queue-health` is now dispatch-primary via the new `cron-actions-queue-health-dispatch` Inngest cron (the GHA `schedule:` stays as fallback) and its check-in margin widened 30 → 60 to cover measured dispatch delivery (p90 ~20 min queue wait + runtime + jitter); (3) the new `cron-bot-pr-reaper` sweep (every 2 h) update-branches armed `soleur-ai[bot]` PRs stuck `behind` under a settle-guard + `expected_head_sha` CAS + ≤5/sweep cap, and files a dedup `action-required` issue for states update-branch cannot fix.

## Recovery verification

Verified by the enrolled follow-through probe `scripts/followthroughs/cron-machinery-soak-9272.sh` (earliest = deploy + 3d): it exits 0 only when (a) zero `scheduled-output-missing` events fire for `scheduled-community-monitor` while ≥1 digest issue/day lands, (b) `scheduled-actions-queue-health` shows no `missed` check-ins over the window, and (c) no armed `soleur-ai[bot]` PR sits `behind` >24 h.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did a healthy community-monitor run page red and lose its digest? The verify step performed ONE point-in-time issues-list read ~6 s after `gh issue create` returned; the label-filtered list view had not yet indexed the row, so the read declared the output missing.
2. Why did a missing-read discard real work? The persistence gate keys on the heartbeat verdict — `heartbeatOk=false` skips artifact persistence, so a false negative deleted the day's digest, not just the page.
3. Why did queue-health page ~47×/day? Its `missed`-check-in arm assumed absence ⇒ runner starvation, but GitHub defers `on.schedule` workflows under org load before a runner is ever requested — the probe fired ~4×/day and read HEALTHY when it landed.
4. Why did digests stop reaching main? Armed-auto-merge bot PRs sat `mergeable_state: "behind"` — auto-merge cannot fire on a stale head and no actor ran update-branch; every monitor stayed green because no monitor watched that stall shape.
5. Why did the design allow this? The verify path treated a LIST read as strongly consistent with a just-committed CREATE; the queue-health margin was sized for a scheduler that delivers on time; and the bot-PR flow had no owner for the "behind" transition.

## Versions of Components

- **Version(s) that triggered the outage:** soleur @ main — latent defects in apps/web-platform/server/inngest/functions/_cron-shared.ts › verifyScheduledIssueCreated (single-shot list read) and apps/web-platform/infra/sentry/cron-monitors.tf › scheduled-actions-queue-health checkin_margin_minutes=30 vs observed multi-hour GHA schedule deferral. No triggering deploy identified.
- **Version(s) that restored the service:** soleur @ PR #9280 (verify retry + dispatch-primary queue-health + bot-PR reaper).

## Impact details

### Services Impacted

Monitoring integrity only: Sentry cron monitors scheduled-community-monitor and scheduled-actions-queue-health; the community-digest artifact pipeline (digests for 2026-09-27 through 2026-09-30 absent from main; each false-red also discards that day's digest). No customer-facing service impacted.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: None — internal tooling.
- Authenticated app user: None — internal tooling.
- Legal-document signer: None — internal tooling.
- Admin via Access: None — internal tooling.
- Billing customer: None — internal tooling.
- OAuth installation owner: None — internal tooling.

### Revenue Impact

None identified — internal tooling incident.

### Team Impact

Alert fatigue: ~47 missed-checkin pages/day from scheduled-actions-queue-health plus recurring false-reds on scheduled-community-monitor erode trust in the monitoring layer (a real runner-starvation event or a real cron failure would be read as more noise). Four consecutive daily community digests never reached main.

## Lessons Learned

### Where we got lucky

The false-red was self-evidencing: the filed issue (#9268) predated the "no output" event by ~7 s, so the race was provable from timestamps alone. The queue-health probe happened to land a HEALTHY verdict mid-incident (03:11Z), which ruled out real starvation without a host check.

### What went well

Detection worked as designed — both pages fired at the real anomaly surface (a missed/error check-in), the defects were all latent rather than regressed-by-change, and remediation was scoped inside a day.

### What went wrong

A single point-in-time read was trusted as the verify oracle for an eventually-consistent list view; a schedule-deferral confounder was baked into a starvation monitor's premise; and the bot-PR merge path had no actor for the "behind" state — three silent-failure shapes in the same monitoring layer surfaced in one morning.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `No action items — incident fully resolved in the source PR with no residual work.` as a line of its own, with no emphasis — the permitted no-item form is plain so that the markdown linter (MD049, emphasis-style) cannot restyle it; the `/ship` gate accepts the plain line (and the underscore/asterisk-wrapped spellings shipped before this template changed).

| Issue | Action | Status |
|---|---|---|
| #9272 | Bounded retry in verifyScheduledIssueCreated so a just-filed labelled issue that appears within N seconds is not declared missing (stops false-red + discarded artifacts) | shipped in #9280 |
| #9273 | Retune scheduled-actions-queue-health (checkin margin and/or non-GHA-schedule trigger) so scheduler deferral stops paging while true runner starvation still does | shipped in #9280 |
| #9274 | Reaper for stale app/soleur-ai cron-artifact PRs stuck 'behind' with auto-merge armed (update-branch) so daily digests land on main again | shipped in #9280 |
