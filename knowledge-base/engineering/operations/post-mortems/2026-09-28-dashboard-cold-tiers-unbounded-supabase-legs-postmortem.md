---
title: "Dashboard cold loads stalled up to ~43s behind unbounded remote Supabase legs that outlived the mw-auth fix"
date: 2026-09-28
incident_pr: 9034
incident_window: "deploy of PR #8984 (sq 9b6b0394) .. merge of PR #9034"
recovery_at: "merge + deploy of PR #9034 — post-deploy probe on the served sha is the close evidence (#8978)"
suspected_change: "cold-start remote Supabase PostgREST/Auth legs on the authenticated document path — present before #8984, exposed by it once the mw-auth tier was fixed and the residual legs became the dominant tier"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - monitoring
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — performance regression only; no personal data processed, exposed or lost"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The authenticated `/dashboard` cold load first-painted in **1.71–43 s** against a
≤500 ms acceptance criterion. PR #8984 had already fixed the middleware-auth
tier (merged `9b6b0394`, deployed); issue #8978 was reopened because the AC
remained unmet. Span-level evidence showed the residual tier was the same
class: remote Supabase PostgREST/Auth calls stalling 20–38 s cold — a
`check_my_revocation` RPC leg (~26–28.5 s), the `resolveIdentity`
`users`/`workspace_members` selects (~20.7–37.5 s), `auth/v1/user` (~3–6 s),
and a hidden remote `/auth/v1/token` refresh inside `getSession()` on expired
tokens. None of these legs carried a bound, so one cold upstream could pin a
document for tens of seconds; concurrent cold misses each paid the full stall
(mount fan-out amplified it).

## Status

resolved — the fix is PR #9034; post-deploy probe evidence is tracked on #8978.

## Symptom

Cold-load probes against the deployed build: doc TTFB 2.5–43.4 s, FCP
2.8–43.6 s across 5 cold + 1 warm samples; the warm sample still read ~2.1–8.7 s.

## Incident Timeline

- **Start time (detected):** post-deploy probe after PR #8984 (~2026-09-27) — #8978 reopened
- **End time (recovered):** merge + deploy of PR #9034 (post-deploy probe pending at write time)
- **Duration (MTTR):** ~1 day from reopened issue to merged fix

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-09-27 | Reopened #8978 — ≤500 ms FCP AC unmet (cold 1.71–38 s, warm 2.08 s). |
| agent | 2026-09-27 | Phase-0 probe + Sentry span pull named the residual tiers: revocation RPC 26–28.5 s, identity selects 20.7–37.5 s, auth/v1/user 3–6 s — all remote stalls, no queueing. |
| agent | 2026-09-27/28 | PR #9034: bounds every leg onto existing degrade arms, dedups concurrent misses, warms the upstream, completes the getUser sweep; review panel + 2 full batteries. |

## Participants and Systems Involved

- `apps/web-platform/middleware.ts` — revocation RPC, T&C select, getUser/getSession legs
- `apps/web-platform/lib/feature-flags/identity.ts` — `resolveIdentity` selects
- `apps/web-platform/server/request-auth.ts` — `verifiedUserId`/`boundedAuthGetUser`/`sessionJwtEmailForVerifiedUser`
- `apps/web-platform/server/{supabase-edge-warmer,index}.ts` — upstream warm-up
- ~70 route files — `auth.getUser()` → `verifiedUserId(req)` sweep
- `scripts/test-all.sh` — orphan watchdog + durable suite logs (incident-adjacent machinery issues #8993/#8940 folded into the same PR)
- Supabase/PostgREST/GoTrue upstream — the cold-stall source

## Detection (+ MTTD)

- **How detected:** the committed authenticated perf probe (`apps/web-platform/scripts/live-verify/perf-probe.ts`) + Sentry `http.client` span reads — in-surface measurement, not a user report.
- **MTTD:** residual tier named within one phase-0 measurement pass of reopening.

## Triggered by

system — cold-start upstream stalls on the production deployment; not user- or market-triggered.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Remote Supabase leg cold-stall dominates the doc tier | Spans: RPC 26–28.5 s, selects 20.7–37.5 s, all inside transactions whose render/dispatch legs were fast | — | Confirmed |
| Request queueing / dispatch delay | — | Receipt→dispatch gap ≈ 0 on every sampled transaction | Refuted |
| Dashboard component mount fan-out | 3 s mw-auth × N mounts observed | Fan-out amplifies but did not produce the 23–38 s document stall | Deferred (#8985, data: fetch-count dominance criterion unmet) |
| Middleware isolate warm-up gap | Stall recurred on warm samples | Warm sample still ~2.1 s — not isolate-shaped | Rejected as primary |

## Resolution

Bounded every Supabase-facing leg (`.abortSignal(AbortSignal.timeout())` on
PostgREST → existing error arms; `Promise.race` on GoTrue legs including the
hidden `getSession()` refresh); in-flight dedup map for concurrent revocation
misses (positive-only verdict cache unchanged); process-scoped upstream
warm-up interval; per-sub grace-strike bound so a sustained outage escalates
to a session-preserving bounce; `auth.getUser()` → `verifiedUserId` sweep
(87 sites, census-ratcheted); durable per-suite logs + parent-death watchdog
for `test-all`.

## Recovery verification

Post-deploy authenticated probe on the served sha: cold TTFB/FCP table
versus the ≤500 ms AC + Server-Timing `mw-*` descriptors + Sentry span
distribution. Tracked as the close evidence on #8978 (issue kept `Ref`, not
`Closes`).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the document stall 23–38 s cold? Remote Supabase legs inside the
   middleware + render path stalled 20–38 s on a cold upstream.
2. Why could one leg pin the whole document? The legs were awaited
   unboundedly — no timeout carried onto a degrade arm.
3. Why was there no bound? "Slow upstream" was treated as a rare edge;
   fail-open/retry was implicit, never measured — until the probe quantified
   the recurring 20–38 s class.
4. Why did the same stall amplify? Concurrent cold misses each paid the full
   stall; nothing shared in-flight work.
5. Why did the residual survive #8984? That fix bounded the mw-auth leg only;
   the sweep assumed auth was the dominant tier, and the remaining legs were
   never span-measured until this incident's phase-0.

## Versions of Components

- **Version(s) that triggered the outage:** deployment containing `9b6b0394` (post-#8984)
- **Version(s) that restored the service:** PR #9034 (merge sha on the served build)

## Impact details

### Services Impacted

- `web-platform` production (`app.soleur.ai`) — authenticated document + API cold path

### Customer Impact (by role)

- Prospect: none observed (public paths unauthenticated, unaffected).
- Authenticated app user: every cold dashboard visit potentially paid multi-second to ~40 s first paint; warm visits ~2 s.
- Legal-document signer: none observed.
- Admin via Access: none.
- Billing customer: degraded chrome risk (identity select stall → prd/null degrade path).
- OAuth installation owner: none observed.

### Revenue Impact

No measured revenue impact; conversion-retention risk on first-run cold loads.

### Team Impact

Multi-hour full-battery gates under sibling contention during the fix; review
panel + two re-verifications.

## Lessons Learned

### Where we got lucky

The residual tier was already instrumented — Sentry span data named the exact
legs on the first pull, no speculative architecture change needed.

### What went well

Measurement-first: phase-0 probe + span pull selected the mechanism (bounds +
dedup + warmth) instead of the assumed component fix; review panel caught the
watchdog fire-order defect and the decline-invite authz hole before merge;
durable-log machinery (#8940) immediately paid for itself diagnosing the first
battery's reds.

### What went wrong

#8984's completion criterion measured only the tier it touched; the residual
legs shipped unbounded, and "getSession() is a local read" was repeated in
comments while its expired-token path is remote. The runner's own EXIT trap
could have disarmed the watchdog mid-escalation had the review not caught the
fire-order inversion.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8978 | Post-deploy probe re-run vs ≤500 ms FCP AC; close with measured table once the served sha verifies | open |
| #8985 | Re-evaluate mount fan-out with fresh fetch-count-vs-document-tier data (deferred-with-data disposition) | open |
| #9117 | GC the durable `SOLEUR_TEST_ALL_LOG_DIR` (mtime-based reap; currently accumulates forever) | open |
| #9118 | `check_my_revocation` RPC-side NULL invitee_email hole (app-layer guard shipped in this PR; SQL fix pending) | open |
