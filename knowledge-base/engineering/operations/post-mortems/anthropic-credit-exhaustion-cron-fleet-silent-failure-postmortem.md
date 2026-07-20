---
title: "claude-eval cron fleet silently no-op'd by Anthropic credit exhaustion, masked by green monitors"
date: 2026-06-29
incident_pr: 5680
incident_window: "2026-06-29 ~10:36Z → ~11:33Z (credit-exhausted window); masking defect latent for weeks prior"
recovery_at: "2026-06-29 ~11:33Z (operator credit top-up + ~2-min billing propagation)"
suspected_change: "none — Anthropic operator-key prepaid balance reached zero; pre-existing heartbeat-masking made it invisible"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - provider billing (Anthropic prepaid balance → 0)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The Anthropic operator API key's prepaid balance reached zero around 2026-06-29 10:36Z. Every Inngest cron that spawns a `claude-eval` child process (agent-native-audit, legal-audit, ux-audit, bug-fixer, and the rest of the output-aware cohort) immediately failed — `claude --print` exited non-zero with `Credit balance is too low` on the very first turn, so each cron did **zero** of its actual work. The failure was **invisible**: the crons returned `{ ok:false }` without throwing (so `routine_runs` recorded `completed`), and several posted a GREEN Sentry cron-monitor check-in ("liveness, not success"). There was no balance alert. The whole claude-eval fleet was a silent no-op with every health surface showing green.

## Status

resolved — the billing cause was cleared by an operator top-up; the structural masking defect is fixed in PR #5680 (#5674).

## Symptom

Operator asked whether the week's crons had recovered after the egress fix (#5413). Investigation found the cron-monitor heartbeats green and `routine_runs` rows `completed`, yet the crons had produced no audit output. Pulling the claude-eval stdout tail from Better Stack revealed `Credit balance is too low` across the cohort.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-29 ~10:36Z | Anthropic operator-key prepaid balance hits 0; first credit-blocked claude-eval exit. |
| system | 2026-06-29 10:36Z–11:31Z | Each scheduled cron fires, claude-eval exits non-zero on turn 1, cron returns `{ok:false}` → `routine_runs` "completed", monitor stays green. |
| agent | 2026-06-29 ~late-AM | Diagnostic session: routine_runs "completed" misread as recovery (twice); corrected via Sentry heartbeats, then Better Stack stdout naming `Credit balance is too low`. |
| human | 2026-06-29 ~11:31Z | Operator tops up the Anthropic credit balance. |
| agent | 2026-06-29 11:31Z | A re-fired cron still credit-blocked (billing-propagation lag). |
| agent | 2026-06-29 ~11:33Z | Direct 1-token probe of the operator `ANTHROPIC_API_KEY` returns HTTP 200 — recovery confirmed. |

## Participants and Systems Involved

Inngest cron substrate (`_cron-shared.ts`, the 4 masked crons + output-aware cohort), Anthropic Messages API (operator key), Sentry cron monitors, `routine_runs` durable run-log, Better Stack (ClickHouse) log pipeline.

## Detection (+ MTTD)

- **How detected:** external/manual — operator question about cron recovery, not an automated alert. No monitor fired because every health surface was green-on-failure.
- **MTTD:** effectively unbounded — the masking defect meant the fleet could fail indefinitely without a page. The credit-exhausted window happened to be caught the same day only because the operator asked.

## Triggered by

provider — Anthropic prepaid balance reaching zero. The **severity** (silent, fleet-wide, unalerted) was caused by the latent heartbeat-masking defect, not the billing event.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Egress fix (#5413) incomplete, dropping cron→Anthropic connections | Concurrent `egress-blocked` Sentry issue firing on Cloudflare 104.16.x.34 | Crons reached Anthropic and got a *billing* error, not a connection drop; egress drops were on a different host set | REJECTED (red herring, tracked separately #5676) |
| Anthropic operator-key credit exhaustion | Better Stack stdout `Credit balance is too low` across the cohort; direct key probe HTTP 200 only after top-up | none | CONFIRMED |

## Resolution

Operator topped up the Anthropic prepaid balance (~11:31Z); recovery confirmed at ~11:33Z by a direct 1-token API probe of the exact operator key (HTTP 200) rather than waiting on a heavy cron (which raced a ~2-min billing-propagation lag). The structural masking defect — the reason this was invisible — is fixed in PR #5680 (#5674): capture the scrubbed failure reason into Sentry + `routine_runs.error_summary`; classify-fatal so a credit/auth/spawn-fault non-zero flips the monitor RED (benign max-turns stays green per #4727); and an hourly canary probe that pages on credit exhaustion from the HTTP body.

## Recovery verification

Direct probe: a 1-token POST to the Anthropic Messages API with the operator `ANTHROPIC_API_KEY` returned HTTP 200 at ~11:33Z. Forward-looking: the new `scheduled-anthropic-credit-probe` monitor (PR #5680) provides a continuous canary; tasks.md P.1 verifies its existence via the Sentry API post-merge.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the whole claude-eval fleet stop working?** The operator Anthropic key's prepaid balance hit zero; every claude-eval exited turn-1 with `Credit balance is too low`.
2. **Why was that invisible?** The crons returned `{ ok:false }` without throwing (run-log recorded "completed") and posted a green "liveness, not success" Sentry heartbeat on non-zero exit.
3. **Why did a non-zero eval exit post green?** The original heartbeat policy was deliberately liveness-only (to avoid the #4730 false-page where `claude --print` exits non-zero on a *healthy* max-turns run) — but it never distinguished a fatal class (credit/auth) from a benign one.
4. **Why was there no balance alert to catch it upstream?** No Anthropic balance/usage canary existed; the only signal was each cron's own (masked) heartbeat.
5. **Why did diagnosis initially misattribute it to egress?** The captured failure reason was `null` (stdout discarded per ADR-033 I5), so the Sentry issue was a generic "spawn exited non-zero"; a concurrent unrelated `egress-blocked` issue supplied a plausible-but-wrong causal story.

## Versions of Components

- **Version(s) that triggered the outage:** pre-#5674 cron substrate (liveness-only heartbeat, stdout-discarding, no credit canary).
- **Version(s) that restored the service:** operator credit top-up restored function; PR #5680 (#5674) restores *observability* so a recurrence pages instead of hiding.

## Impact details

### Services Impacted

All claude-eval crons (agent-native-audit, legal-audit, ux-audit, bug-fixer + output-aware cohort) produced no work during the credit-exhausted window. No user-facing app surface was affected — these are internal autonomous maintenance crons.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none — claude-eval crons are internal maintenance jobs, not request-path.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None directly. Indirect: autonomous maintenance (audits, bug-fixing) paused for the window; no customer-visible degradation.

### Team Impact

One diagnostic session consumed re-deriving a cause that a captured failure reason would have made obvious in seconds.

## Lessons Learned

### Where we got lucky

The operator happened to ask about cron health the same day; the masking defect could otherwise have hidden a fleet-wide stall indefinitely.

### What went well

Better Stack retained the claude-eval stdout, which carried the definitive cause once we thought to read it. The direct key-probe gave a clean recovery signal without waiting on the propagation-lagged crons.

### What went wrong

Three independent health surfaces (routine_runs status, Sentry heartbeat colour, the absence of a balance alert) all reported healthy while the fleet was fully down. The captured failure reason was `null`, which actively misdirected diagnosis toward egress.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5674 | Capture scrubbed failure reason into Sentry + `routine_runs.error_summary`; classify-fatal heartbeat (credit/auth/spawn-fault → RED, benign max-turns → green); hourly Anthropic credit canary probe (shipped in PR #5680). | open |
| #5692 | Pre-exhaustion spend-vs-budget alert (page BEFORE balance hits zero, not just at exhaustion). | open |
| #5676 | Residual container egress drops to Cloudflare 104.16.x.34 after #5413 — the diagnosis red herring; confirm non-causal and resolve. | open |
| #5675 | cron-follow-through-monitor: ready workspace with NULL `github_installation_id` unreachable by reconcile (separate defect surfaced during diagnosis). | open |
| #5728 | `scheduled-community-monitor` check-ins were `missed` 2026-06-13→06-21 *despite* real digests being produced (a check-in delivery/timing defect distinct from credit exhaustion) — surfaced 2026-06-29 while reconciling the "failing since June 13" Sentry alert; the credit regime (this incident) was 06-22→06-29. Runbook H10 gained an un-mute/re-enable step for the prolonged-outage case in the same remediation. | open |
