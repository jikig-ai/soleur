---
title: "Waitlist signups blocked end-to-end: Buttondown embed Turnstile, then subscriber-firewall aggressive mode"
date: 2026-06-11
incident_pr: 5153
incident_window: "2026-06-08T15:38Z – 2026-06-11T08:27Z (~65h, two overlapping causes)"
recovery_at: "2026-06-11T08:27Z"
suspected_change: "External: Buttondown moved the keyless embed endpoint behind Cloudflare Turnstile; Buttondown account Firewall in aggressive auditing mode blocked API-sourced subscribes"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - provider
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability outage only; no personal-data exposure, no unauthorized access (visitor emails failed to REACH the processor; nothing leaked)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The marketing waitlist (pricing page + every shared-doc CTA banner — the single top-of-funnel conversion surface) rejected every signup with the generic "Something went wrong" state for roughly 65 hours across two overlapping causes: (1) Buttondown moved its keyless embed-subscribe endpoint behind Cloudflare Turnstile, killing the original proxy (fixed by the v1-API migration, merged 2026-06-09 11:20Z); (2) the replacement authenticated v1 subscribes were then rejected by Buttondown's account-level **Firewall** feature in `aggressive` auditing mode — API-sourced subscribes are risk-scored on the CALLER's IP (the Hetzner server, score 0.6 ≥ the 0.5 aggressive threshold) when no `ip_address` is supplied. A stale prior-session diagnosis ("server egress is blocked; needs a Cloudflare Worker or SSH") delayed the real fix; the container egress allowlist had already shipped `api.buttondown.com` (merged 2026-06-10) and was never the cause.

## Status

resolved

## Symptom

`POST /api/waitlist` returned 502 for every visitor; the CTA banner showed "Something went wrong. Please try again." Sentry `WEB-PLATFORM-2F` ("Buttondown subscribe failed: 400", warning level) accumulated 22 events 2026-06-09 → 2026-06-11. Buttondown's actual response (invisible in logs by status-only design): `{"code":"subscriber_blocked","detail":"This subscriber was blocked by your firewall."}`.

## Incident Timeline

- **Start time (detected):** 2026-06-09T10:01Z (first Sentry WEB-PLATFORM-2F event; cause-1 window opened earlier — last successful embed-form signup 2026-06-08T15:38Z)
- **End time (recovered):** 2026-06-11T08:27Z
- **Duration (MTTR):** ~65h wall-clock from last good signup; ~46h from first Sentry event

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-08T15:38 | Last successful signup lands via embed form (subscriber record). Buttondown Turnstile gating breaks the keyless embed proxy at some point after. |
| agent | 2026-06-09T11:20 | PR #5077 merged: migrate `/api/waitlist` to authenticated v1 subscribers API. Post-deploy, signups STILL fail — now `subscriber_blocked` 400 → 502 (Sentry WEB-PLATFORM-2F, 20 events on 06-09). |
| agent | 2026-06-09/10 | Prior session misdiagnoses the residual failure as server egress blockage; proposes Buttondown-embed / CF-Worker / SSH paths. Operator declines SSH; session lost before a path was chosen. |
| human | 2026-06-11T~08:10 | Operator resumes via /soleur:go; asks for a no-SSH fix of the "egress" problem. |
| agent | 2026-06-11T08:15 | Re-verification: egress allowlist already contains `api.buttondown.com` (Tier-2 firewall, merged 2026-06-10); prod probe still 502 in 2.6s; Sentry shows the 400 REACHES Buttondown — egress ruled out. |
| agent | 2026-06-11T08:25 | Replay of the byte-identical subscribe with the prd `BUTTONDOWN_API_KEY` from Doppler surfaces `subscriber_blocked` — Buttondown's account Firewall, `auditing_mode: aggressive`. |
| agent | 2026-06-11T08:27 | `PATCH /v1/newsletters/news_3wpkj1rdcz9yvavzrctks7ztgp {"auditing_mode":"enabled"}` (blocks only risk ≥1.0). |
| agent | 2026-06-11T08:29 | Recovery verified: prod `POST /api/waitlist` → 200 `{ok:true}`; subscriber created (`pricing-waitlist` tag, `type=unactivated` double opt-in, risk_score 0.6 now passing). Sentry issue resolved. |
| agent | 2026-06-11T~10:00 | Hardening PR (this PR): forward visitor `cf-connecting-ip` as `ip_address` so signups survive a future auto-reversion to aggressive ("attack mode"). |

## Participants and Systems Involved

Operator (harry), Claude Code agent. Systems: web-platform `/api/waitlist` route (Hetzner-hosted container), Buttondown v1 API + account Firewall, Sentry (jikigai-eu/web-platform), Doppler (prd secrets), Cloudflare (edge, `cf-connecting-ip`).

## Detection (+ MTTD)

- **How detected:** External/manual — operator observed the banner failure; Sentry WEB-PLATFORM-2F was recording but its warn-level events did not page.
- **MTTD:** hours (first Sentry event 06-09 10:01Z; operator-driven investigation began same day).

## Triggered by

provider — two independent Buttondown-side changes/behaviors (Turnstile gating of the embed endpoint; Firewall aggressive-mode scoring of API-caller IPs).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Server egress to Buttondown blocked (prior session) | Pre-#5089 timing; 502s | Sentry 400s prove responses RETURN from Buttondown; allowlist contains `api.buttondown.com`; direct replay reaches API | rejected |
| BUTTONDOWN_API_KEY missing/invalid | — | Key present in Doppler prd; replay authenticates (400 not 401) | rejected |
| Buttondown subscriber Firewall blocks API-sourced subscribes | Replay returns `subscriber_blocked`; `auditing_mode: aggressive` on the newsletter; clean email + visitor ip_address passes under `enabled` | — | CONFIRMED |

## Resolution

`auditing_mode` PATCHed `aggressive` → `enabled` via Buttondown API (no SSH, no dashboard). Hardening in the source PR: route forwards the visitor's real IP (`ip_address`) so Buttondown scores the residential visitor (<0.5) instead of the datacenter server (0.6), keeping signups alive even if attack mode re-escalates the account to aggressive.

## Recovery verification

Live prod probe 2026-06-11T08:29Z: `POST https://app.soleur.ai/api/waitlist` (browser-shaped headers) → `200 {"ok":true}`; `GET /v1/subscribers/harry22510@gmail.com` shows `creation_date` seconds later, `source=api`, `tags=["pricing-waitlist"]`, `type=unactivated` (double opt-in pending). Sentry WEB-PLATFORM-2F marked resolved (HTTP 200 on PUT). The test subscriber is retained as the verification artifact for PR #5077's unchecked post-deploy box.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did waitlist signups fail? → Buttondown returned `subscriber_blocked` 400 to every v1 subscribe; the route correctly mapped the unexpected status to 502.
2. Why did Buttondown block every subscriber? → The account Firewall was in `aggressive` auditing mode (blocks risk ≥0.5) and API subscribes carried no `ip_address`, so Buttondown scored the Hetzner server IP (0.6).
3. Why was the server IP being scored? → The #5035 proxy design (API key server-side, CSP excludes buttondown.com) replaced the browser→Buttondown direct submission, silently substituting the server IP for the visitor IP in Buttondown's risk model.
4. Why did diagnosis take ~46h from first Sentry event? → (a) status-only logging (correct for PII) hid the `subscriber_blocked` body; (b) a prior session anchored on an egress-firewall hypothesis that became stale when #5089 shipped the allowlist, and the session was lost before re-verification; (c) Sentry warn-level events did not page.
5. Why did the stale hypothesis persist across sessions? → Session context was lost (operator shut the conversation) and the resumed work initially trusted the recorded diagnosis instead of re-probing the live system first.

## Versions of Components

- **Version(s) that triggered the outage:** Buttondown-side changes (external, unversioned); web-platform main at #5077 (correct code, blocked upstream).
- **Version(s) that restored the service:** No code change required for recovery (vendor-side `auditing_mode` PATCH); hardening lands in PR #5153.

## Impact details

### Services Impacted

`/api/waitlist` (pricing page + shared-doc CTA banner). No other service affected; no data loss; no degradation of authenticated app surfaces.

### Customer Impact (by role)

- Prospect: **primary impact** — every waitlist signup attempt for ~65h bounced with a generic error; leads silently lost (top-of-funnel n is small at this stage; Buttondown shows no gap-window subscribers).
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

Indirect only (lost top-of-funnel leads during a pre-revenue waitlist phase). Not quantifiable; assumed small at current traffic.

### Team Impact

~3 operator/agent sessions consumed across diagnosis attempts, including one full dead-end infra arc (Worker/SSH paths).

## Lessons Learned

### Where we got lucky

- Buttondown's blocked-subscriber handling drops the attempt pre-creation, so no half-created subscriber state needed cleanup.
- The aggressive-mode score (0.6) was close to the `enabled` threshold (1.0), so a one-field vendor-side PATCH restored service instantly without code.

### What went well

- Status-only logging discipline held — no PII leaked into logs/Sentry even under multi-day failure.
- The no-SSH observability stack (Sentry token + Doppler-readable secrets) was sufficient for full diagnosis and recovery, validating `hr-no-ssh-fallback-in-runbooks`.
- The route's fail-direction was correct throughout: graceful JSON 502, idempotent visitor messaging.

### What went wrong

- A vendor-side account setting (`auditing_mode`) was a single point of failure with zero observability on our side; nothing distinguished "egress blocked" from "vendor rejected" in the 502 the visitor saw.
- Sentry warn-level mirrors did not page; 20 events accumulated on day one without escalation.
- The stale egress diagnosis crossed a session boundary unverified, costing a day (see learning `2026-06-11-buttondown-subscriber-firewall-blocks-api-signups.md`; runbook `cron-egress-blocked.md` now carries the "upstream 4xx ≠ egress" discriminator + the Doppler-key replay technique).

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

_No action items — incident fully resolved in the source PR with no residual work._
