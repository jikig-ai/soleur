---
title: "Inngest cutover blocked: op=enumerate returned an undiagnosable HTTP 500"
date: 2026-06-17
incident_pr: 5493
incident_window: "2026-06-17 (single read-only dry-run attempt; no production mutation)"
recovery_at: "2026-06-17 (fix merged; post-deploy enumerate re-verification gated to operator)"
suspected_change: "PR #5483 (#5450 no-SSH cutover orchestration) — enumerate script + workflow shipped with an epoch from-default and a body-discarding consumer"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - read-only dry-run (op=enumerate) returned opaque 500
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

During the Phase-2 live cutover of the durable Inngest backend (#5450), the very first step — `op=enumerate` (a read-only enumeration of still-armed reminders, run via the no-SSH HMAC webhook) — returned an **opaque HTTP 500 with an empty body**. The cutover was correctly halted on this read-only step. **No production state was mutated**: no quiesce, no deploy, no volume wipe; the operator's armed reminder (#5432) stayed safe on the old backend the entire time. The failure was operational (a planned maintenance op could not proceed and could not be diagnosed without SSH) rather than user-facing.

## Status

resolved — the 500 is now diagnosable (workflow dumps the response body cause), the root cause (epoch `filter.from`) is fixed, and the fix auto-redeploys to the host on merge.

## Symptom

`gh workflow run cutover-inngest.yml --field op=enumerate` → the host script's `/hooks/inngest-enumerate-reminders` returned HTTP 500 with an empty body; the workflow's enumerate branch printed `enumerate returned HTTP 500` with no cause. No-SSH diagnosis was impossible.

## Incident Timeline

- **Start time (detected):** 2026-06-17, first live `op=enumerate` attempt
- **End time (recovered):** 2026-06-17, fix merged (PR #5493)
- **Duration (MTTR):** same-session (no production impact during the window)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-17 | Ran the live cutover; `op=enumerate` returned an opaque 500. |
| agent | 2026-06-17 | Halted the cutover (read-only step failed; refused to proceed blind). |
| agent | 2026-06-17 | Filed #5492; built the fix (PR #5493) — body-dump, epoch clamp, no-leak, deploy-trigger registration. |

## Participants and Systems Involved

Self-hosted Inngest v1.19.4 (GraphQL `eventsV2`), `adnanh/webhook` v2.8.2 (HMAC hooks on `deploy.soleur.ai`), `cutover-inngest.yml` GitHub Action, the 4 webhook-delivered inngest cutover host scripts.

## Detection (+ MTTD)

- **How detected:** the operator-run read-only dry-run (`op=enumerate`) — the deliberate first step before any mutation — surfaced the 500 immediately.
- **MTTD:** immediate (first invocation).

## Triggered by

system — a latent defect in the just-merged orchestration (#5483), exposed on first real invocation against prod (R4: `workflow_dispatch` couldn't be pre-merge-validated on a feature branch, and the epoch from-default was never exercised by the recent-`from` fixtures/schema probe).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Webhook captured stdout only; script wrote errors to stderr | initial diagnosis | `adnanh/webhook` v2.8.2 uses `CombinedOutput()` (both streams) | refuted |
| Consumer discarded the response body | rearm branch `cat`s its body; enumerate did not | — | confirmed |
| Epoch `filter.from` rejected by inngest → no `.data.eventsV2` → exit 1 → 500 | clamp test RED on epoch / GREEN on 365d | — | confirmed |

## Resolution

PR #5493: (1) `cutover-inngest.yml` enumerate branch now `cat`s `/tmp/enum-body` and folds the cause into `::error::`; (2) `inngest-enumerate-reminders.sh` clamps `filter.from` off the 1970 epoch to a 365-day lookback (`ENUMERATE_FROM` overrides); (3) the malformed-response path surfaces only payload-free error messages + data key names; (4) the 4 inngest scripts are registered in `deploy_pipeline_fix` triggers so the fix auto-redeploys.

## Recovery verification

Post-merge auto-apply redelivers the fixed script to the host; the operator then re-runs `gh workflow run cutover-inngest.yml --field op=enumerate` and confirms a JSON array (or a diagnosable `::error::` cause) — tracked under #5450's cutover retry.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the cutover stall?** `op=enumerate` returned an opaque 500.
2. **Why opaque?** The workflow's enumerate branch discarded the response body on non-200 (unlike the rearm branch).
3. **Why a 500 at all?** The script defaulted `eventsV2 filter:{from}` to the 1970 epoch, which inngest v1.19.4 rejects as out-of-range → no `.data.eventsV2` → exit 1.
4. **Why was the epoch default never caught?** The fixtures + the v1.19.4 schema probe both used a recent `from`; the runtime-only default value was never exercised by a test.
5. **Why did the initial fix premise misfire?** The "webhook is stdout-only" hypothesis was wrong (it's `CombinedOutput()`); deepen-plan's dogfooded reviewer caught it before any code, re-framing the fix as a consumer-discards-body bug.

## Versions of Components

- **Version(s) that triggered:** PR #5483 (`vinngest-v1.1.14` orchestration; enumerate epoch default).
- **Version(s) that restored:** PR #5493.

## Impact details

### Services Impacted

The Inngest durable-backend **cutover procedure** (a planned maintenance op) — blocked, not degraded. No live service impacted.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none — the operator's armed reminder (#5432) stayed on the old backend, never at risk; no reminder was dropped or double-fired.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

One session of cutover work blocked + redirected into building the diagnosability fix.

## Lessons Learned

### Where we got lucky

The cutover's first step was **read-only** by design — the 500 surfaced before any quiesce/deploy/wipe touched prod. A mutation-first sequence would have left prod mid-cutover with no diagnosis.

### What went well

The read-only-dry-run-first sequencing; the refusal to proceed blind; deepen-plan's dogfooded reviewer catching the wrong stdout-only premise before code.

### What went wrong

A runtime-only default (epoch `from`) shipped untested; the enumerate consumer discarded the response body (the rearm branch already did it right — asymmetry); the 4 cutover scripts weren't in the deploy-trigger set, so the fix would not have auto-deployed.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5450 | Post-deploy: operator re-runs `op=enumerate` (recovery verification), then completes the live cutover. | open |
| #5495 | Inline Better Stack + Sentry log/issue read so the next no-SSH op failure is diagnosable without a code change. | open |
