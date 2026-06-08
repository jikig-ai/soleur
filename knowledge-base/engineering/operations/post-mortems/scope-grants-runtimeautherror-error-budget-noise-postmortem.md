---
title: "RuntimeAuthError error-level Sentry noise on /dashboard/settings/scope-grants (no outage)"
date: 2026-06-08
incident_pr: feat-one-shot-runtime-auth-error-scope-grants
incident_window: "2026-06-07 18:14 CEST (first Sentry event) → 2026-06-08 (fix merged)"
recovery_at: "2026-06-08 (per-cause severity split merged)"
suspected_change: "PR #4949 (927b0643) relocated the Concierge BashAutonomousToggle onto the scope-grants settings page, adding a resolveBashAutonomous() call per render. Its RuntimeAuthError catch mirrored to Sentry via reportSilentFallback at level=error for ALL causes, including the fully-recovered transient jwt_mint blip."
brand_survival_threshold: none
status: resolved
triggers:
  - telemetry-severity-miscalibration
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

A production Sentry issue (`d87684243c554592953ea9148f46f4e6`, web-platform, `level: error`, **`handled: yes`**, feature tag `pino-mirror`) fired `RuntimeAuthError: Authentication unavailable; retry shortly` on `GET /dashboard/settings/scope-grants` RSC prefetches. This was **not an operational outage** — the page rendered correctly throughout and there was zero user-facing impact. The "incident" was error-budget pollution: a fully-recovered, fail-closed transient was being emitted at `error` severity. Captured here per the standing rule that every detected production error gets a post-mortem, even when it is telemetry hygiene rather than downtime.

## Status

resolved

## Symptom

Recurring `error`-level Sentry events (`handled: yes`) for `RuntimeAuthError` originating from the scope-grants settings page during RSC prefetch. The events polluted the error budget and could mask genuine errors; no user ever experienced a broken page (the toggle defaulted to the safe `false`, approval gate ON).

## Incident Timeline

- **Start time (detected):** 2026-06-07 18:14 CEST (16:14 UTC) — first Sentry event / high-priority alert email
- **End time (recovered):** 2026-06-08 (fix merged)
- **Duration (MTTR):** ~same-day from operator triage to merged fix

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-07 16:14 | Sentry high-priority alert email for `d87684243c554592953ea9148f46f4e6`. |
| human | 2026-06-08 | Operator routed the alert into `/soleur:go` → `/soleur:one-shot`. |
| agent | 2026-06-08 | Code-traced the throw→catch→mirror chain; reframed root cause from "unhandled crash" (alert prose) to "severity miscalibration". |
| agent | 2026-06-08 | Shipped per-cause severity split + tests; PR #5006. |

## Participants and Systems Involved

`apps/web-platform/server/resolve-bash-autonomous.ts`, `lib/supabase/tenant.ts` (founder-JWT mint, `RuntimeAuthError`), `server/observability.ts` (`reportSilentFallback`/`warnSilentFallback`), Sentry (`pino-mirror`).

## Detection (+ MTTD)

- **How detected:** monitoring — Sentry "Send a notification for high priority issues" rule emailed the operator. No SSH, no dashboard archaeology required.
- **MTTD:** immediate (alert fired on the first occurrence).

## Triggered by

PR #4949 (`927b0643`) mounted `BashAutonomousToggle` on the scope-grants page, adding a `resolveBashAutonomous(user.id)` call on every render. The helper mints a founder-scoped Supabase JWT (`getFreshTenantClient`); on a transient mint failure (GoTrue 429, RPC blip, missing secret) it throws `RuntimeAuthError`. The existing catch failed closed to the safe `false` and **deliberately** mirrored to Sentry — but via `reportSilentFallback`, which captures at the default `level: error` for every cause.

## Root Cause

Severity miscalibration, not a crash. A transient, fully-recovered, fail-closed degradation was emitted as an `error`-level handled event. The `handled: yes` flag was the tell: a `try/catch` deliberately captured it, so the correct question was "is `error` the right level?" — not "why is it crashing?". The alert prose ("handle gracefully / redirect") was misleading; the page already handled it gracefully.

## Remediation

Per-cause severity split in the existing catch block: `jwt_mint` (transient) → `warnSilentFallback` (warning, off the error budget); `denied_jti` (session revoked) and `rotation` (rate-ceiling) stay `reportSilentFallback` (error) so on-call keeps the actionable signal. Both carry a queryable `extra.code`. No redirect added (would bounce the founder off their own settings page on a transient blip); fail-closed posture unchanged. PR #5006.

## Art. 33 / 34 Assessment

- **art_33_triggered:** false — no personal-data breach. The mirror already pseudonymizes `userId → userIdHash` (Recital 26); the `RuntimeAuthError` message is the sanitized constant "Authentication unavailable; retry shortly".
- **art_34_triggered:** false — no data subject is affected; user-facing behavior was byte-identical before and after.

## Follow-ups

- **AC7 (post-deploy, automated):** on the next natural `jwt_mint` occurrence, confirm via Sentry that the event lands at `level: warning` while `denied_jti`/`rotation` remain `error`. No synthetic prod trigger exists; verify on natural occurrence. Tracked in PR #5006 test plan.
- No alerting-gap or write-site-sweep follow-ups: the fix is complete and self-contained.

## Lessons

Read the throw→catch→mirror chain in code before trusting a Sentry alert's prose diagnosis. A `handled: yes` error-level event from a graceful fail-closed mirror is a `warn`-vs-`error` calibration question, not a behavioral bug. See `knowledge-base/project/learnings/bug-fixes/2026-06-08-handled-error-sentry-event-from-fail-closed-mirror-is-severity-not-crash.md`.
