---
title: "Waitlist signup 502 — Buttondown moved the public embed endpoint behind Cloudflare Turnstile"
date: 2026-06-09
incident_pr: 5077
incident_window: "unknown start (Buttondown Turnstile rollout) → 2026-06-09 (fix merged)"
recovery_at: "on deploy of PR #5077"
suspected_change: "External: Buttondown gated its public embed-subscribe endpoint behind Cloudflare Turnstile"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - provider
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `human` — Operator did this directly.

# Incident Overview

The marketing waitlist banner (`CtaBanner`, rendered on the pricing page and every shared document) failed for every visitor: `POST /api/waitlist` returned a Cloudflare-synthesized gateway 502 and the banner showed "Something went wrong. Please try again." No signup could complete. Externally triggered — Buttondown moved its public `embed-subscribe` endpoint behind Cloudflare Turnstile, which a server-side same-origin proxy cannot solve. No Soleur deploy caused it.

## Status

resolved — fix in PR #5077 (migrate to Buttondown's authenticated v1 API, which is not behind Turnstile).

## Symptom

`POST https://app.soleur.ai/api/waitlist` → `502`, `server: cloudflare`, `content-type: text/plain`, body `error code: 502` (NOT the app's own `{"error":"upstream_unavailable"}` JSON). Banner displays "Something went wrong. Please try again."

## Incident Timeline

- **Start time (detected):** 2026-06-09 (operator reported the banner error while using a shared document)
- **End time (recovered):** on deploy of PR #5077
- **Duration (MTTR):** ~hours from detection to fix-merged (true onset unknown — silent external regression)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-09 | Operator hit "Something went wrong" submitting an email on the shared-doc waitlist banner; reported the 502 XHR trace. |
| agent | 2026-06-09 | Reproduced against prod; isolated CF-502 (origin failure) vs app-JSON-502; direct Buttondown probe revealed a 400 + Turnstile challenge page. |
| agent | 2026-06-09 | Fixed: migrated `subscribeToWaitlist` to the authenticated v1 API + timeout + fail-closed key read (PR #5077). |

## Participants and Systems Involved

`/api/waitlist` route (`apps/web-platform/app/api/waitlist/`), Buttondown (US email processor), Cloudflare (edge in front of both app.soleur.ai and buttondown.com).

## Detection (+ MTTD)

- **How detected:** external/manual — operator using the feature, not a monitor. The app returned the broken upstream call as a gateway 502 with a warn-level Sentry mirror only when the app's own catch was reached; the gateway-level 502 produced no app-side error event, so no alert fired.
- **MTTD:** unknown — the regression was silent (no alert on a third-party endpoint contract change).

## Triggered by

provider — Buttondown added a Cloudflare Turnstile challenge to its public embed-subscribe endpoint.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| App route handler bug | — | Early-exit paths returned correct app JSON (403/405); only the upstream-call path failed | rejected |
| Origin/whole-app outage | — | `GET /` healthy (307, 0.2s) | rejected |
| Buttondown public endpoint now requires Turnstile | Direct POST to embed-subscribe returns 400 + HTML "Verify Your Subscription" loading challenges.cloudflare.com/turnstile | — | confirmed |

## Resolution

Rewrote `subscribeToWaitlist` to call Buttondown's authenticated v1 REST API (`POST api.buttondown.com/v1/subscribers`, `Authorization: Token`), which is not behind Turnstile. Added `AbortSignal.timeout(5s)` (a future stall now degrades to the app's JSON 502, not a gateway hang), a fail-closed call-time key read, and a tightened duplicate-400 predicate. `type` is omitted to preserve double opt-in.

## Recovery verification

Post-deploy: `POST /api/waitlist` with a valid email returns `200 {ok:true}` and the subscriber appears (status unconfirmed, pending double opt-in) under the `pricing-waitlist` tag. Covered by the PR's post-merge ⏳ test-plan item and the `/soleur:postmerge` health check.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did signups fail? `POST /api/waitlist` returned a gateway 502.
2. Why a gateway 502? The origin's upstream call to Buttondown failed/hung; the request died before the app's own error branch returned JSON.
3. Why did the upstream call fail? Buttondown's public embed-subscribe endpoint returned a 400 + Turnstile challenge a server cannot solve.
4. Why were we calling a Turnstile-gated endpoint? `subscribeToWaitlist` proxied Buttondown's public browser-form endpoint server-side.
5. Why was a public browser-form endpoint chosen? It was keyless (no secret to wire) at build time — but public form endpoints can sprout bot defenses at any time. The authenticated REST API is the supported server-to-server path.

## Versions of Components

- **Version(s) that triggered the outage:** web-platform @ 0.117.3 (and earlier — onset coincides with Buttondown's external Turnstile rollout, not a Soleur version)
- **Version(s) that restored the service:** the release containing PR #5077

## Impact details

### Services Impacted

Marketing waitlist signup only (`/api/waitlist`). No authenticated product surface, data, auth, or billing path affected.

### Customer Impact (by role)

- Prospect: HIGH — could not join the early-access waitlist from the pricing page or any shared doc; submission always errored.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

Indirect — lost top-of-funnel leads for the duration. No direct revenue path.

### Team Impact

Low — single-session diagnosis + fix.

## Lessons Learned

### Where we got lucky

The app already returned a generic error to the client and logged status-only, so no key or PII leaked despite the failing upstream call.

### What went well

Fast root-cause via the CF-502-vs-app-JSON-502 distinction (the gateway 502's `server: cloudflare`/`text/plain` shape localized the fault to the origin/upstream layer, not the handler) plus a direct Buttondown probe that surfaced the Turnstile challenge.

### What went wrong

A silent third-party contract change broke a user-facing feature with no alert. The failure manifested as a gateway 502 that never reached the app's Sentry mirror, so nothing paged.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
