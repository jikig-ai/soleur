---
title: "Concierge conversation dies mid-stream — premature idle-watchdog runner_runaway on long single tool"
date: 2026-06-12
incident_pr: 5208
incident_window: "intermittent; reproducible whenever a single Concierge tool call exceeds ~90s (large Read / slow model round-trip)"
recovery_at: "2026-06-12 (on merge of PR #5208)"
suspected_change: "pre-existing behavior of the server idle watchdog (state.runaway, DEFAULT_WALL_CLOCK_TRIGGER_MS=90s) in apps/web-platform/server/soleur-go-runner.ts — re-armed only by assistant blocks and tool_use_result, never by the SDK tool_progress heartbeat"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - operator dogfooding report (Concierge chat surfaced repeated "Agent stopped responding after: …" cards while the debug stream was still actively running cat commands)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The Soleur Concierge conversation repeatedly died mid-answer with "Agent stopped responding after: Exploring project structure" / "Agent stopped responding after: Reading file" while the agent was still legitimately working (the debug stream kept running `cat` commands reading source files). This is an availability/reliability defect on the product's core conversation surface — no data was exposed.

## Status

resolved — fixed in PR #5208 (server idle-watchdog re-arm on the SDK `tool_progress` heartbeat).

## Symptom

A Concierge turn shows one or more red "Agent stopped responding after: <last activity>" cards mid-stream, then the stream tears down and the client reconnects — even though the agent was actively executing a single long tool call (large `Read`, slow Anthropic round-trip) the whole time.

## Incident Timeline

- **Start time (detected):** 2026-06-12 (operator report; behavior latent since the watchdog logic predated the SDK `tool_progress` heartbeat being consumed on this surface)
- **End time (recovered):** 2026-06-12 (on merge of PR #5208)
- **Duration (MTTR):** same-day (root-caused, fixed via TDD, and shipped in one session)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-12 | Operator reported the Concierge "conversation is still not working" — repeated mid-stream "Agent stopped responding" cards with a screenshot. |
| agent | 2026-06-12 | Root-caused to the server idle watchdog (`state.runaway`, 90s) firing during a single long tool with no intermediate block/result; the SDK `tool_progress` heartbeat was being dropped at the runner dispatch switch. |
| agent | 2026-06-12 | Fixed (re-arm `state.runaway` on `tool_progress`), reviewed (6 agents), shipped PR #5208. |

## Participants and Systems Involved

Soleur Concierge (cc / `soleur-go`) WS runner (`apps/web-platform/server/soleur-go-runner.ts`); the Claude Agent SDK stream (`SDKToolProgressMessage`); the operator (tenant-zero, dogfooding).

## Detection (+ MTTD)

- **How detected:** external/manual — operator dogfooding report with a screenshot. No automated alert fired (the watchdog "fire" is logged as a `log.warn`, not paged).
- **MTTD:** unknown for first occurrence (latent); same-session for this report.

## Triggered by

system — the server idle watchdog mis-classified "one slow but progressing tool" as "agent went idle."

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Server `state.runaway` idle window (90s) fires during a single long tool because it is re-armed only by assistant blocks / `tool_use_result`, not by the mid-tool `tool_progress` heartbeat | The card text names the in-flight tool; the debug stream was actively running `cat`; `agent-runner.ts:1901` already consumes `tool_progress` while `soleur-go-runner.ts` dropped it | none | confirmed |

## Resolution

Added a `tool_progress` branch to the runner's `consumeStream` dispatch switch that calls `armRunaway(state)` (guarded by `!state.closed && !state.awaitingUser`), re-arming the per-block idle window on the SDK mid-tool heartbeat. `state.turnHardCap` (10-min absolute ceiling) is untouched, and a genuinely hung tool (no heartbeat) still trips `idle_window` at 90s — hung-tool detection preserved (pinned by merge-blocking test AC2b).

## Recovery verification

Unit suite green: 37 affected tests pass (watchdog reset AC1, hung-tool-still-fires AC2b, hard-cap intact AC3, debug-panel autoscroll AC4–6); full repo suite 110/110 suites pass. Post-merge, a drop in `runner_runaway` `reason=idle_window` fire frequency at stable traffic is the live success signal (existing `log.warn` at `soleur-go-runner.ts`).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the conversation die mid-answer?** The server fired `runner_runaway` (`reason: idle_window`) and tore down the stream.
2. **Why did the idle watchdog fire?** `state.runaway` (90s) elapsed with no re-arm.
3. **Why was it not re-armed?** It was re-armed only on assistant-block boundaries and `tool_use_result` synthetic messages; a single tool that runs >90s before producing its first result emits neither.
4. **Why was the available signal ignored?** The SDK emits a `tool_progress` mid-tool heartbeat (already flowing in via `includePartialMessages: true`), but the `soleur-go-runner` dispatch switch dropped it at the "ignored at V1" branch — unlike the sibling `agent-runner.ts`, which already consumes it.
5. **Why wasn't the asymmetry caught earlier?** No test pinned "long single tool must not trip the idle window," and the two runners' reset surfaces had drifted without a parity check.

## Versions of Components

- **Version(s) that triggered the outage:** all Concierge builds prior to PR #5208.
- **Version(s) that restored the service:** PR #5208 merge to main.

## Impact details

### Services Impacted

Soleur Concierge conversation (cc / `soleur-go` surface) only. No data, auth, billing, or migration surface touched.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: Concierge turns involving a >90s single tool (large file reads, slow model round-trips) died mid-answer with a trust-destroying "Agent stopped responding" card; the agent had to be re-prompted. No data loss.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None directly; reputational/trust risk on the core chat surface (single-user-visible).

### Team Impact

Dogfooding friction: the operator could not complete Concierge conversations on non-trivial prompts.

## Lessons Learned

### Where we got lucky

The fix re-used an SDK signal already flowing into the runner — no new infra, secret, or SDK option needed. The sibling `agent-runner.ts` provided a verified precedent.

### What went well

Root-caused against source before coding; TDD with a non-vacuous merge-blocking hung-tool test (AC2b); 6-agent review confirmed the DoS-safety (10-min `turnHardCap` bounds `tool_progress` flooding) and surfaced a downstream client-surface residual.

### What went wrong

The two runner surfaces drifted (one consumed `tool_progress`, one didn't) with no parity test; the watchdog "fire" is a `log.warn`, not a paged signal, so the first occurrence went undetected until manual report.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #5214 | Forward `tool_progress` to the client on the cc surface so the client 45s watchdog cannot independently paint a terminal error bubble at ~90s on long single-tool turns (pre-existing client-surface residual, exposed more often now that the server keeps the stream alive). | open |
