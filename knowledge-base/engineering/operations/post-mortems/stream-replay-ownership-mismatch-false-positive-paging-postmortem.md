---
title: "stream-replay op=ownership-mismatch error-level false-positive paging"
date: 2026-06-15
incident_pr: "#5320"
incident_window: "2026-06-14 (PR #5290 merge) → 2026-06-15 (fix merged)"
recovery_at: "2026-06-15 (PR #5320 deploy)"
suspected_change: "PR #5290 / commit 5c908a8a6 (ADR-059 stream-since-disconnect replay buffer)"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The `resume_stream` reconnect handler (chat WebSocket, ADR-059 replay buffer, introduced by PR #5290) emitted **error-level** Sentry events with `feature=stream-replay`, `op=ownership-mismatch` for **benign reconnect races** — a deferred-creation conversation row not yet materialized, and a transient `getCurrentRepoUrl` null on a tenant-mint blip. These false positives paged operations and risked masking a genuine cross-user/cross-repo signal under the noise. No user-facing degradation occurred: the client always rendered the correct honest history-refetch fallback.

## Status

resolved — fixed in PR #5320 (severity recalibrated by cause; client gate keys on materialization-proof).

## Symptom

Production Sentry issue `4bbd7379131f4399b784d0b8465fb2a7`: `level=error`, `feature=stream-replay`, `op=ownership-mismatch`, `environment=production`, first seen 2026-06-15 10:38 CEST on `web-platform@0.129.1`.

## Incident Timeline

- **Start time (detected):** 2026-06-15 (Sentry high-priority notification)
- **End time (recovered):** 2026-06-15 (PR #5320 merged + deployed)
- **Duration (MTTR):** ~hours (same-day detection → fix)

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-14 | PR #5290 (ADR-059) merges; error-level `op=ownership-mismatch` emit goes live. |
| system | 2026-06-15 08:38 | First production error-level event captured to Sentry. |
| human | 2026-06-15 | Operator forwards the Sentry notification; `/soleur:go` routes to one-shot fix. |
| agent | 2026-06-15 | Root cause traced (severity miscalibration + transient-null), fix implemented + reviewed. |
| agent | 2026-06-15 | PR #5320 merged; severity recalibrated, client gate added. |

## Participants and Systems Involved

`apps/web-platform` chat WebSocket (`server/ws-handler.ts` `handleResumeStream`, `server/current-repo-url.ts`, `lib/ws-client.ts`); Sentry (web-platform project); the ADR-059 stream-replay buffer.

## Detection (+ MTTD)

- **How detected:** Sentry high-priority issue notification (monitoring system).
- **MTTD:** < 1 day from the emit going live (#5290 merged 2026-06-14; first event 2026-06-15).

## Triggered by

system — a code change (PR #5290) that classified every `resume_stream` ownership/repo-scope guard miss as error-level, without distinguishing benign reconnect races from genuine cross-user/cross-repo attempts.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Severity miscalibration: benign reconnect races emitted at error level | git blame attributes the emit solely to #5290/5c908a8a6; two benign causes reproduce the zero-row / null-repo paths | The lookup is correctly owner-scoped (`.eq("user_id", userId)`) — not an attribution bug | confirmed |
| Cited relation to leader-liveness commit b1c7d1eff (#5306) | — | b1c7d1eff is client-side `chat-state-machine.ts` only; does not touch the emit | disconfirmed |

## Resolution

Recalibrated severity by cause: genuine DB error / cross-repo stays error-level (`reportSilentFallback`, `cause=db-error` / `cause=url-differs`); the benign deferred-not-materialized race is warning (`warnSilentFallback`, `cause=not-materialized`, observable not silenced); a transient `currentRepoUrl` null emits no handler mirror (already mirrored upstream, now downgraded to warning). Switched the conversation lookup `.single()`→`.maybeSingle()` so zero-row is distinguishable from a DB error. Added a client gate so the reconnect `resume_stream` is sent only when the conversation row provably exists (`sessionKind==="resumed"` OR `"fresh"` with a rendered server-stamped frame), removing the dominant benign source while preserving mid-turn gap-frame recovery.

## Recovery verification

Pre-merge: 40 affected vitest tests + full web-platform suite (9918) green; `tsc` clean; a source-contract drift-guard (`sentry-stream-replay-severity-op-contract.test.ts`) pins the genuine-error ops at error level and fails closed on a future downgrade. Post-deploy: AC13/AC14 verify (read-only Sentry API) that `feature=stream-replay` error-rate drops to near-zero and `cause=not-materialized` warning volume drops ≥90% over the 48h window (owned by `/soleur:postmerge` + the #5324 re-eval criterion).

## Root Cause(s) — 5-Whys

1. Why did ops get paged? An error-level Sentry event fired for a benign reconnect. 2. Why error-level? PR #5290 mirrored every `resume_stream` guard miss at error. 3. Why was a benign race a guard miss? Deferred-creation rows materialize lazily, and a transient tenant-mint null was misread as a repo-scope mismatch. 4. Why weren't these distinguished? The single emit collapsed three causes (benign-deferred, transient-null, genuine-attack) into one op+level. 5. Why did the plan-time design miss it? ADR-059 classified ownership-mismatch as blanket-P1 without enumerating the recoverable reconnect-race conditions.

## Versions of Components

`web-platform@0.129.1` (commit `6a54dda7a`); emit introduced by `5c908a8a6` (#5290).

## Impact details

No user-facing impact — the client always rendered the correct honest history-refetch fallback. Impact was confined to observability: false-positive error-level paging and the risk of masking a genuine cross-user/cross-repo signal. No personal data exposed (the Sentry `extra` carries a hashed `userId` + `conversationId`, unchanged by this fix), so Art. 33/34 do not apply.

## Lessons Learned

- A client-side gate added to suppress a server false-positive must key on the **existence proof** of the resource, not a proxy correlated with it (session origin). See `knowledge-base/project/learnings/best-practices/2026-06-15-severity-recalibration-client-gate-must-key-on-materialization-proof.md`.
- RLS row-denial returns zero rows (not SQLSTATE 42501) when the role holds the table SELECT grant — relevant when classifying DB errors by severity.
- Blanket-P1 severity for a reconnect guard floods alerts; enumerate recoverable vs page-worthy causes at design time.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5324 | Distinguish owned-by-another from row-absent at `resume_stream` (privileged probe), gated on the AC14 warning-volume-drop criterion. | open |
