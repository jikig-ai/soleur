---
title: "scheduled-community-monitor missed check-ins 2026-06-13→06-21 despite digests produced (heartbeat delivery/timing)"
date: 2026-06-30
incident_pr: 5729
incident_window: "2026-06-13 → 2026-06-21 (9 days)"
recovery_at: "2026-06-22 (missed regime ended; durable delivery fix ships in PR #5729 + ADR-068/#5686)"
suspected_change: "none — latent design defect (single terminal heartbeat with no pre-swap drain, pre-ADR-068)"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/observability incident, no personal-data exposure (cron heartbeat delivery only)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The `scheduled-community-monitor` Sentry cron monitor recorded **`missed`** check-ins every day from **2026-06-13 → 06-21** even though the Inngest cron `cron-community-monitor` produced a real daily digest issue each of those days. Last healthy `ok` check-in was 2026-06-12. The check-in layer (which the Sentry alert keys off) and the GitHub-digest layer disagreed: the monitor was RED-by-`missed` while work was actually completing. This is an observability-reliability incident — for 9 days a genuine community-monitor outage in that window would have been indistinguishable from this benign-but-broken state, and Sentry's auto-mute/disable clock ran against the false `missed`.

## Status

resolved — the dominant cause (mid-run SIGKILL) is removed by ADR-068/#5686 (graceful cron drain, merged 2026-06-29); PR #5729 hardens the orthogonal throw/dropped-POST delivery classes fleet-wide as defense-in-depth; a 7-day post-deploy delivery soak is enrolled (#5731).

## Symptom

Daily Sentry `missed` check-ins for `scheduled-community-monitor` 2026-06-13→06-21 with a full daily digest issue filed each day (real digests, not the FAILED self-report fallback). `missed` (Sentry-server-generated "job didn't check in") — NOT a client `?status=error` — meaning the single terminal `sentry-heartbeat` step never executed.

## Incident Timeline

- **Start time (detected):** 2026-06-13 (first `missed` after last-ok 2026-06-12)
- **End time (recovered):** 2026-06-22 (missed regime ended; durable fix 2026-06-29/06-30)
- **Duration (MTTR):** ~9 days of `missed`; root-caused + durably fixed 2026-06-30

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-13→06-21 | Daily `missed` check-ins while digests produced. |
| human | 2026-06-29 | Issue #5728 filed describing the delivery/timing defect. |
| agent | 2026-06-30 | Phase-0 evidence pull (routine_runs + Sentry checkins) → SIGKILL-dominant verdict. |
| agent | 2026-06-30 | PR #5729: bounded-retry POST + final-attempt error heartbeat (fleet-wide). |

## Participants and Systems Involved

`cron-community-monitor` Inngest function; the shared `_cron-shared.ts` heartbeat substrate; the Sentry Crons monitor `scheduled-community-monitor`; `routine_runs` (Supabase run-log middleware); Better Stack (log warehouse). Claude Code (agent) investigated + fixed.

## Detection (+ MTTD)

- **How detected:** Sentry missed-check-in alert ("failing since 2026-06-13"), reconciled against the GitHub digest layer which showed healthy output — the layer disagreement was the tell.
- **MTTD:** alert fired at the first missed margin (same day); root-cause diagnosis deferred until the #5728 investigation (2026-06-30).

## Triggered by

system — a mid-run container swap / deploy / OOM SIGKILLed the long (~50-min) `claude-eval` before the function reached its single end-of-run `sentry-heartbeat` step.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| H2 mid-run SIGKILL before the terminal heartbeat | Zero `routine_runs` terminal rows for 06-16→06-21 while ~20 sibling crons logged normally; missed (not error) | — | CONFIRMED dominant |
| H1 run duration > 30-min margin (06-13→06-15) | margin was 30 min then; eval budget 50 min | routine_runs + Better Stack blind for those days | plausible co-contributor |
| H3 swallowed/failed OK POST | — | no `completed` rows to pair with a POST-failure event | refuted for the window |
| H4 dispatch/queue delay (shared account slot) | — | siblings dispatched fine; start_lag <65s | refuted |

## Resolution

Dominant cause (SIGKILL) removed by ADR-068/#5686 (graceful cron drain before container swap, 2026-06-29). PR #5729 closes the remaining delivery classes fleet-wide: (1) `postSentryHeartbeat` inspects `resp.ok` + bounded-retries 5xx/network/timeout under a 25s budget (H3); (2) `finalizeOutputAwareHeartbeat` posts a loud terminal `?status=error` on a final-attempt throw instead of a silent `missed`, memoization-safe across `retries:1`. `in_progress` two-phase check-in remains ADR-033-I8-rejected.

## Recovery verification

`missed` regime ended 2026-06-22 (incidentally — the function began fast-failing before the kill-prone eval window, a separate regression tracked in #5732). Durable verification: 7-day post-deploy delivery soak (no `missed`/`timeout` check-ins) enrolled in the follow-through sweeper (#5731, `scripts/followthroughs/community-monitor-checkin-soak-5728.sh`).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the monitor show `missed`?** The terminal `sentry-heartbeat` step never executed.
2. **Why didn't it execute?** The ~50-min `claude-eval` was SIGKILLed mid-run (container swap/deploy/OOM) before reaching the heartbeat — and a throw inside the catch-less inner try would also have propagated past it.
3. **Why was a mid-run kill possible?** No graceful drain protected in-flight crons from container swaps before ADR-068/#5686 (landed 2026-06-29, after the window).
4. **Why was the kill silent (`missed` not `error`)?** The function posts exactly one check-in at the very end (no `in_progress` beacon, by ADR-033-I8 design), so any death during the eval window leaves no check-in at all.
5. **Why was the throw/dropped-POST class also unprotected?** `postSentryHeartbeat` was fire-and-forget (never inspected `resp.ok`) and the inner try had no catch, so a transient 5xx or a pre-heartbeat throw produced a silent `missed`.

## Versions of Components

- **Version(s) that triggered the outage:** pre-ADR-068 deploy substrate (no cron drain); `_cron-shared.ts` single fire-and-forget heartbeat.
- **Version(s) that restored the service:** ADR-068/#5686 (drain) + PR #5729 (delivery hardening).

## Impact details

### Services Impacted

`scheduled-community-monitor` observability only. The daily community digest WAS produced throughout the window — no user-facing community feature was down.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: degraded observability — a false-RED monitor that could mask a real outage and consume the Sentry auto-mute clock.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Operator alert-fatigue + a 9-day window where a real community-monitor outage would have been indistinguishable from the benign `missed` noise.

## Lessons Learned

### Where we got lucky

No genuine community-monitor outage occurred during the 9-day blind window, so the indistinguishability never cost a missed real incident.

### What went well

The output-aware GitHub-digest layer (#4714/#4730) provided an independent signal that contradicted the `missed` check-ins, which is what surfaced the layer disagreement and made the diagnosis tractable.

### What went wrong

A single terminal heartbeat with no `in_progress` beacon makes any mid-run death silently `missed`; the heartbeat POST was fire-and-forget; and the run-log middleware predated the window, so the authoritative liveness layer was blind for 06-13→06-15.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5731 | 7-day post-deploy delivery soak (no `missed`/`timeout` check-ins) enrolled in the follow-through sweeper. | open |
| #5732 | Investigate the distinct daily `error` + ~300ms fast-fail regime since 2026-06-22 (digest likely not generated post-credit-topup). | open |
