---
title: "web-1's LUKS at-rest monitor was never installed and stayed dark for nine weeks"
date: 2026-09-27
incident_pr: 9044
incident_window: "2026-07-20 (first real cutover run meant to install it) → merge of PR #9044"
recovery_at: "merge of PR #9044 (per-merge SSH apply installs and arms the timer)"
suspected_change: "PR #6610 (938863a9d8) — put the only installer at the tail of workspaces-cutover.sh, after app_canary"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - observability-gap
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data was exposed; a detection control was missing, the encryption state it checks was not changed"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

`luks-monitor.timer` is web-1's daily, host-local re-test that `/workspaces` is still on the LUKS
volume. It was never installed. Its units and `/usr/local/bin/luks-monitor` were delivered only by
the tail of `workspaces-cutover.sh`, which runs after `app_canary`, and no real cutover run reached
that tail. The daily host signal was therefore absent from 2026-07-20 until this fix, with nothing
alerting on its absence.

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

No `luks-monitor.service` output reached Better Stack or Sentry. The token installer's state print in
apply run 36005279546 (2026-09-24) read `0 timers listed.` and an empty `UnitFileState=` for the
timer — no unit file, not a disabled one.

## Incident Timeline

- **Start time (detected):** 2026-09-24T08:47:58Z (#8706 filed)
- **End time (recovered):** merge of PR #9044
- **Duration (MTTR):** ~3 days from detection to the fix merging; ~9 weeks of dark monitor before detection

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-17 | PR #6610 ships the cutover mechanism; the monitor installer sits at the tail of `workspaces-cutover.sh`. |
| agent | 2026-07-20T22:07Z | Cutover run 29782780158 passes the host canary and dies in `app_canary`, before the installer. |
| agent | 2026-07-23T09:35Z | Cutover run 29995956562 dies in `app_canary` the same way. |
| human | 2026-09-24T08:47Z | Operator files #8706: the timer shows no output off-box. |
| agent | 2026-09-24T13:23Z | Apply run 36005279546 prints `0 timers listed.` and an empty `UnitFileState=`. |
| agent | 2026-09-27 | PR #9044: Terraform installs and arms the timer; a Better Stack alert pages on its absence. |

## Participants and Systems Involved

web-1 (`soleur-web-platform`), `workspaces-cutover.sh`, `apply-web-platform-infra.yml`,
`workspaces-luks-verify.yml`, Better Stack Logs source 2457081, the shared LUKS heartbeat.

## Detection (+ MTTD)

- **How detected:** manual report — the operator noticed the host timer never reported (#8706). No monitor fired.
- **MTTD (mean time to detect):** ~9 weeks (2026-07-20 → 2026-09-24).

## Triggered by

system — a delivery path placed after a step that never succeeded.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Timer installed but disabled or failing | none | `UnitFileState=` empty (a disabled unit reads `disabled`); `0 timers listed.` | rejected |
| Timer never installed | apply run 36005279546 state print; both canary-passing cutover runs died before the installer | none | confirmed |

## Resolution

PR #9044 adds `terraform_data.luks_monitor_install`, targeted by the per-merge SSH apply, which
delivers the probe, emit helper and units, writes the DSN line, arms and asserts the timer, and kicks
one run. `logtail_exploration_alert.luks_monitor_host_timer_dark` pages when no host-unit `OK:` row
lands in 27 h, scoped to web-1 so the verify job's and web-2's rows cannot mask it.

## Recovery verification

After merge: the apply run's state print shows `UnitFileState=enabled` with `NextElapse` in
00:00–00:30 UTC, and the alert's own predicate returns ≥1 row after the kick. Closure is mechanical:
`scripts/followthroughs/luks-monitor-host-timer-8706.sh` passes only after three consecutive UTC
nights of host-unit `OK:` rows, and the sweeper then closes #8706.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was there no host output? The timer and probe were never installed on web-1.
2. Why never installed? The only installer ran at the end of `workspaces-cutover.sh`, after `app_canary`.
3. Why did that not run? Every real cutover run died at or before `app_canary`.
4. Why did nothing notice? The shared heartbeat had a second pusher (the verify job over SSH), and
   the heartbeat manifest's arming guard matched a line of code that had never executed.
5. Why was the delivery placed there? The monitor's delivery was coupled to a one-shot migration
   rather than owned by the per-merge apply that owns every other web-host monitor.

## Versions of Components

- **Version(s) that triggered the outage:** PR #6610 (938863a9d8) onward.
- **Version(s) that restored the service:** PR #9044.

## Impact details

### Services Impacted

The daily host-local LUKS at-rest re-test on web-1. The encryption state it checks was not changed.
The CI verify job (`workspaces-luks-verify.yml`) kept pushing its own `OK:` rows over SSH (9 in the
7 days before the fix), so an at-rest regression would still have been visible on that job's cadence.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none.
- Authenticated app user: no functional impact; a daily detection control for their workspace data's at-rest encryption was missing.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

A security control was reported as armed while it did not exist on the host.

## Lessons Learned

### Where we got lucky

The verify job's SSH path kept producing at-rest evidence, so the gap was a missing second signal,
not a total loss of detection.

### What went well

The token installer's state print recorded the empty `UnitFileState=`, which made the root cause
provable from CI logs without host access.

### What went wrong

- A standing monitor's only delivery path lived behind a migration step that never succeeded.
- A static guard counted the arming line as present without evidence it had ever executed.
- The unit declared `RequiresMountsFor=/mnt/data`, which would have mounted the fstab-named volume on
  its first start; it had never run, so this was never reviewed as live behaviour.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `No action items — incident fully resolved in the source PR with no residual work.` as a line of its own, with no emphasis — the permitted no-item form is plain so that the markdown linter (MD049, emphasis-style) cannot restyle it; the `/ship` gate accepts the plain line (and the underscore/asterisk-wrapped spellings shipped before this template changed).

| Issue | Action | Status |
|---|---|---|
| #8706 | Confirm three consecutive nights of host-unit `OK:` rows after merge (follow-through enrolled; closes automatically) | open |
| #9045 | A post-canary cutover abort leaves the LUKS dead-man armed with no recorded outcome | open |
