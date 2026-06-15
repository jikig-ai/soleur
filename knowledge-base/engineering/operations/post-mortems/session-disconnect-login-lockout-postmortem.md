---
title: "Session disconnect (revocation-gate 503/forced-logout) + login lockout (GoTrue email_sent=2/hr)"
date: 2026-06-15
incident_pr: 5323
incident_window: "Symptom 1 latent since 2026-05-25 (#4345 revocation gate); Symptom 2 latent since GoTrue defaults were never raised; both surfaced to the operator ~2026-06-15"
recovery_at: "2026-06-15 (code fix merged); Symptom 2 fully recovers only after the AC9 GoTrue ceiling apply — tracked in #5330"
suspected_change: "PR #4345 (#4307 revocation gate, middleware.ts, 2026-05-25) introduced 503-for-all + forced-logout on transient failures; configure-auth.sh never set rate_limit_* so GoTrue ran at email_sent=2/hr"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

Two independent production-affecting auth behaviors, both surfaced by the operator (tenant-zero) on 2026-06-15 as "soleur disconnects me from the website and gets easily blocked with log[in] attempts":

1. **Session disconnect.** The #4307 workspace-member revocation gate in `apps/web-platform/middleware.ts` (shipped in PR #4345, 2026-05-25) fail-CLOSED to **HTTP 503 for every authenticated request** on any `check_my_revocation` RPC error, and force-cleared cookies → `/login` on JWT-decode hiccups (`malformed_jwt` / `no_iat`). A transient Supabase connectivity blip or an unusually-shaped-but-valid token therefore manifested as "the site signed me out / stopped working."
2. **Login lockout.** `apps/web-platform/supabase/scripts/configure-auth.sh` set **zero** `rate_limit_*` fields, so GoTrue ran at its defaults. The measured prd actual (Management API GET, 2026-06-15) was `rate_limit_email_sent = 2/hour` **project-wide** — the entire project could send only two sign-in codes per hour, so a few retry/multi-tab cycles locked everyone out.

## Status

resolved — code fix merged in PR #5323 (Symptom 1 fully; Symptom 2 copy + ceiling-raise script). Symptom 2's runtime recovery is the GoTrue ceiling apply (AC9), tracked in #5330.

## Symptom

Authenticated users bounced to `/login` mid-session (Symptom 1); sign-in code requests returning "Too many sign-in attempts" after only a few tries (Symptom 2).

## Incident Timeline

- **Start time (detected):** 2026-06-15 (operator report; latent since 2026-05-25 for Symptom 1)
- **End time (recovered):** 2026-06-15 (code) / pending AC9 apply (#5330) for Symptom 2 runtime
- **Duration (MTTR):** ~same-day from report to fix-merged

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-15 | Operator reported session disconnect + login blocking via /soleur:go. |
| agent | 2026-06-15 | Root-caused to the #4307 revocation gate (503/forced-logout) + GoTrue email_sent=2/hr; measured prd actuals via Management API GET. |
| agent | 2026-06-15 | Fixed middleware grace-on-transient, raised GoTrue ceilings in configure-auth.sh (2→100 / 30→150), softened OTP copy; PR #5323. |

## Participants and Systems Involved

Next.js 15 App Router middleware (`apps/web-platform/middleware.ts`), Supabase GoTrue auth, Supabase Postgres (`check_my_revocation` RPC, migration 067), the OTP login flow (`lib/auth/useOtpFlow.ts`, `error-messages.ts`).

## Detection (+ MTTD)

- **How detected:** External/manual — operator (tenant-zero) report. NOT caught by a monitor (the 503-for-all path emitted a Sentry op but no threshold alert fired; the email_sent=2/hr lockout had no alert).
- **MTTD:** Symptom 1 latent ~3 weeks (shipped 2026-05-25, reported 2026-06-15).

## Triggered by

user (operator report) — surfacing a latent system condition.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Symptom 1 = revocation-gate 503-for-all on transient RPC error + forced logout on decode hiccup | middleware.ts read confirms fail-closed 503 on `revokeError` + cookie-clear→/login on malformed/no-iat | none | confirmed |
| Symptom 2 = GoTrue email_sent ceiling too low | `grep -c rate_limit configure-auth.sh` → 0; Management API GET shows prd `rate_limit_email_sent=2/hr` | none | confirmed |
| Symptom 1 = clock-skew false-positive revocation | — | migration 067's strict `>` is deliberately deny-favoring; a never-removed user has no row to match | rejected |

## Resolution

PR #5323: (1) revocation gate now grants **grace** (allow through, re-check next request, distinct Sentry op) on transient RPC errors and decode hiccups — the genuine `revoked=true` path stays fail-closed; (2) `configure-auth.sh` raises `rate_limit_email_sent` 2→100/hr and `rate_limit_verify` 30→150/hr (defense relaxation, ceilings named); (3) softened the OTP lockout copy to surface the ~1-minute recovery window. The actual removal boundary is RLS `is_workspace_member` (deletes the row), so grace does not re-open the #4307 leak — see `knowledge-base/project/learnings/security-issues/2026-06-15-revocation-gate-is-defense-in-depth-rls-is-the-removal-boundary.md`.

## Recovery verification

- Symptom 1: vitest `middleware.revocation-redirect.test.ts` — transient RPC error → no 503 / no logout (AC1); genuine revocation still fail-closed (AC2). Full webplat suite green (9901 passed).
- Symptom 2: AC9 re-runs `configure-auth.sh` against prd, then Management API GET confirms `rate_limit_email_sent == 100` / `rate_limit_verify == 150` (tracked in #5330).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the site sign users out? → middleware returned 503 / cleared cookies. 2. Why? → the revocation gate fail-CLOSED on transient RPC errors and decode hiccups. 3. Why fail-closed there? → the #4307 gate (correctly) treats revocation as a security boundary, but conflated "RPC errored / can't decode" with "is revoked". 4. Why did that conflation ship? → the gate's design optimized for the genuine-revocation case and the transient-failure blast radius wasn't separated. 5. Root: the middleware gate was treated as THE removal boundary when RLS `is_workspace_member` already enforces it — so fail-closed on transient errors added collateral logouts without adding security.

For Symptom 2: GoTrue's `rate_limit_*` were never set, so an aggressive project-wide default (`email_sent=2/hr`) silently governed production sign-in capacity.

## Versions of Components

- **Version(s) that triggered:** revocation gate from PR #4345 (2026-05-25); GoTrue config with zero `rate_limit_*` since inception.
- **Version(s) that restored:** PR #5323 (middleware grace + copy) + AC9 GoTrue config apply (#5330).

## Impact details

### Services Impacted

Authenticated web app (session continuity) + sign-in (OTP email codes).

### Customer Impact (by role)

- Prospect: none (login page reachable).
- Authenticated app user: Symptom 1 — bounced to /login mid-session on a transient DB blip or odd token; worst case site-wide 503 during a DB blip.
- Legal-document signer: same as authenticated user.
- Admin via Access: unaffected (Access bypasses app auth).
- Billing customer: indirect — could not reach the app during a logout/lockout window.
- OAuth installation owner: unaffected directly.

### Revenue Impact

Indirect/none measured — single-operator (tenant-zero) product at this stage; the risk is demo-killing trust loss.

### Team Impact

~1 session of root-cause + fix.

## Lessons Learned

### Where we got lucky

The over-aggressive fail-closed never coincided with a sustained Supabase outage, so the 503-for-all stayed mostly latent; and grace does not re-open the removal leak because RLS independently denies removed members.

### What went well

Code-tracing (not a synthesized live repro) found both root causes quickly; the Management API GET surfaced the real `email_sent=2/hr` value that the plan had assumed was 30.

### What went wrong

Both conditions were latent and monitor-invisible: the 503-for-all emitted a Sentry op but no threshold alert; the email_sent=2/hr ceiling had no alert at all. Detection was a human report, not a monitor.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #5330 | Apply the raised GoTrue ceilings to prd (+ dev) via configure-auth.sh after CPO sign-off, then verify via Management API GET (AC9 — Symptom 2 runtime recovery). | open |
