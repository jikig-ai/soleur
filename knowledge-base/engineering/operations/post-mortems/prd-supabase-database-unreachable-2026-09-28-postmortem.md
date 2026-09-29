---
title: "prd Supabase database unreachable 2026-09-28"
date: 2026-09-28
incident_pr: 9184
incident_window: "2026-09-28T16:12Z → 2026-09-28T16:49:25Z"
recovery_at: "2026-09-28T16:49:25Z"
suspected_change: "None identified. No deploy, migration or infra apply ran in the onset window. This is the second occurrence of the same signature in 13 days (first: 2026-09-15, postmortem beside this file); an earlier same-day window (10:34Z–10:37Z) also fired unnoticed."
brand_survival_threshold: single-user incident
status: resolved
triggers: []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability outage, no personal-data breach"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The production Supabase project's Postgres stopped serving for about 37 minutes, so sign-in and every data-backed page of app.soleur.ai failed — the second occurrence of the identical signature in 13 days (first: 2026-09-15). This time the database-readiness keyword monitor DID fire — the Better Stack `app_health` monitor (id 4226366, armed by #7884/ADR-222) opened an incident 7 minutes after onset — but its only delivery channel is email, so the alert sat unread in an inbox and nobody was paged. The outage was again found by accident, by an agent reading `/health` while investigating an unrelated failed deploy job, and cleared by an operator-approved project restart. The root cause is platform-side and not yet determined; a Supabase support ticket was drafted (`knowledge-base/engineering/operations/ticket-drafts/supabase-postgres-hang-recurring-2026-09.md`).

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

- Postgres logs stop mid-stream — the same signature as 2026-09-15.
- Management API health: `db`, `auth` and `rest` UNHEALTHY while `pooler` stays ACTIVE_HEALTHY.
- app.soleur.ai `/health` returned `status: ok` with `supabase: error`.
- The Better Stack `app_health` keyword monitor (id 4226366) detected the outage at 16:19:09Z (+7 min) and opened an incident — delivered to email only (`email = true`, `call`/`sms`/`push = false`, `policy_id` gated on an unset `var.betterstack_paid_tier`), so nobody was paged.
- An earlier same-day window, 10:34Z–10:37Z, showed the same signature and also went unnoticed.

## Incident Timeline

- **Start time (detected):** 2026-09-28T16:12Z
- **End time (recovered):** 2026-09-28T16:49:25Z
- **Duration (MTTR):** ~37 min

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 10:34Z–10:37Z | Earlier same-day occurrence of the same signature: db/auth/rest UNHEALTHY, pooler ACTIVE_HEALTHY; the project recovered without intervention. Unnoticed — reconstructed from platform logs after the fact. |
| agent | ~16:12Z | Postgres logs stop mid-stream; `db` goes UNHEALTHY. Incident start. |
| agent | 16:19:09Z | Better Stack `app_health` keyword monitor (id 4226366) opens an incident — the keyword `"supabase":"connected"` stopped matching `/health`. Detection worked; the incident routes to email only, so no human is paged. |
| agent | ~16:35Z | Agent notices `/health` `supabase: error` while chasing an unrelated failed deploy job and begins diagnosis. |
| agent | ~16:37Z | Management API health read: `db`, `auth`, `rest` UNHEALTHY; `pooler` ACTIVE_HEALTHY — the 09-15 signature modulo `storage` (also unhealthy on 09-15, which is Postgres-dependent; the watchdog deliberately observes only db/auth/rest/pooler). |
| agent-with-ack | ~16:43:32Z | With operator authorization, Management API `POST /v1/projects/ifsccnjhymdmidffkzhl/restart` issued; the project goes to restarting. |
| agent | ~16:48:49Z | Management API reports services healthy again. |
| agent | ~16:49:25Z | app.soleur.ai `/health` reads `supabase: connected`. Recovered. |

## Participants and Systems Involved

- Operator (single founder), who authorized the restart.
- Claude Code session that detected the outage via `/health` and ran diagnosis and recovery.
- Supabase prd project `ifsccnjhymdmidffkzhl` (soleur-web-platform, eu-west-1): Postgres, PostgREST, GoTrue auth, Supavisor pooler.
- Better Stack `app_health` monitor (id 4226366), which detected but could not page.
- Sentry — not a factor in detection.

## Detection (+ MTTD)

- **How detected:** monitoring system detected it (Better Stack `app_health` incident at 16:19:09Z, +7 min) but the alert was delivered to an email inbox nobody was watching; the effective detection was manual — an agent reading `/health` ~23 minutes after onset.
- **MTTD (mean time to detect):** ~7 min to a monitoring system; ~23 min to a responder. The detection gap the 09-15 remediation (#7884) closed worked; the gap that remained is DELIVERY — email is not a wake path.

## Triggered by

provider — one of user / system / market movement / provider.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| A change we shipped (deploy, migration, infra apply) broke the database | — | No deploy, migration or infra apply ran in the onset window; identical signature to 09-15 which was also change-free | Rejected |
| Supabase platform-wide incident | Platform-side symptoms; second occurrence in 13 days | Public status page showed no matching incident; signature is project-local (pooler stays healthy while Postgres hangs) | Rejected as platform-wide; project-local platform fault remains open |
| Project-local Postgres hang on the default Micro compute (resource exhaustion: memory, connections) | Identical signature recurring: Postgres halts mid-stream while the pooler stays healthy; only a project restart recovers; Micro is the smallest compute class | No compute or memory metrics are readable through the available API; the earlier 10:34Z–10:37Z window self-recovered without a restart | Open — most likely, unconfirmed; support ticket drafted |

## Resolution

With operator authorization, the project was restarted through the Supabase Management API at ~16:43:32Z. Services reported healthy at ~16:48:49Z and the app read `supabase: connected` at ~16:49:25Z — the same recovery path as 09-15, about 6 minutes from restart to healthy.

## Recovery verification

- Management API health: services ACTIVE_HEALTHY at ~16:48:49Z.
- app.soleur.ai `/health`: `supabase: connected` at ~16:49:25Z.
- The Better Stack incident closed by itself after the monitor's `recovery_period` (180 s) of passing checks.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was the app down?** PostgREST and GoTrue could not reach Postgres, so sign-in and every data-backed request failed.
2. **Why could they not reach Postgres?** The project's Postgres instance halted abruptly (logs stop mid-stream), while the separate Supavisor pooler process stayed ACTIVE_HEALTHY — the identical signature to 09-15.
3. **Why did Postgres stop serving?** Undetermined, platform-side. Recurrence on the same project inside 13 days, plus an unnoticed self-recovering window earlier the same day (10:34Z–10:37Z), strengthens the project-local platform-fault hypothesis on the Micro compute class; a support ticket was drafted to ask Supabase for the fault class and any platform-side correlation.
4. **Why did it last ~37 minutes?** Detection fired at +7 min but delivered to email only; the remediation designed after 09-15 closed the DETECTION gap, not the DELIVERY gap — `app_health` carries `email = true`, `call/sms/push = false`, and its `policy_id` escalation is gated on `var.betterstack_paid_tier`, which is unset. Recovery then waited on a human who was never paged; the only path that found it was an agent reading `/health` while chasing an unrelated failed deploy.
5. **Why does the paging path end at an inbox?** The Better Stack Responder seat that would route incidents to Slack/SMS/phone was deferred in `expenses.md` (#3960) on the trigger "first incident with user-visible latency from email-only routing" — this incident is that trigger firing, the second time it has fired.

Final root cause: **platform-side Postgres hang (cause undetermined; ticket drafted), prolonged to ~37 minutes because the readiness alert delivers to email only and recovery requires a human in the loop.** Both halves are remediated in #9168 / PR #9184: Slack native integration + a measured `push = true` flip make incidents reach the operator's phone, and a bounded auto-restart watchdog removes the human from the recovery path on this exact proven signature.

## Versions of Components

- **Version(s) that triggered the outage:** None on our side. No deploy, migration or infra apply coincided with either window (10:34Z or 16:12Z).
- **Version(s) that restored the service:** No code change. Supabase project restart via the Management API at ~16:43:32Z.

## Impact details

### Services Impacted

app.soleur.ai sign-in (Supabase auth), every data-backed page and API route (PostgREST), and server-side jobs that read or write Postgres. The marketing site soleur.ai was unaffected. The public status page `soleur-ai.betteruptime.com` recorded the incident.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: unaffected — soleur.ai returned 200 throughout.
- Authenticated app user: could not sign in or load conversations, workspaces or KB data for about 37 minutes (plus ~3 minutes in the unnoticed 10:34Z–10:37Z window). No data loss was observed.
- Legal-document signer: T&C acceptance writes would have failed during the window; no evidence of a partial write.
- Admin via Access: no admin surface depends on this path; not affected.
- Billing customer: billing pages that read Postgres would have failed. No payment-provider writes are known to have been lost. Unverified.
- OAuth installation owner: GitHub webhook event recording (`processed_github_events`) would have failed during the window; whether GitHub redelivered those events is unverified.

### Revenue Impact

Unknown / N/A — but the brand-cost vector is "we couldn't reach ourselves": an autonomous-engineering product that pages an inbox while its product is down is the worst shape of the outage, ahead of the raw minutes.

### Team Impact

About 40 minutes of operator and agent time diverted to diagnosis and recovery.

## Lessons Learned

### Where we got lucky

An agent happened to be chasing an unrelated failed deploy job and read `/health`. Without that coincidence, the email-only alert would have sat unread far longer — the 09-15 incident went ~89 minutes the same way.

### What went well

- The #7884 remediation DID deliver detection: the keyword monitor opened an incident 7 minutes after onset, versus ~60 minutes of blindness on 09-15. Detection is fixed; delivery is not.
- Diagnosis was fast and read-only: `/health`, Management API per-service health, and platform logs pinned the signature in minutes, and the earlier same-day window plus the 09-15 incident gave an exact-match recurrence pattern.
- The production write (restart) was again taken only after explicit operator authorization.

### What went wrong

- Detection without delivery: `app_health` routes to email only — `call`, `sms` and `push` are false and `policy_id` escalation is gated on an unset `var.betterstack_paid_tier` — so a working alarm produced a notification nobody saw. The `expenses.md` Responder deferral trigger (#3960, "first incident with user-visible latency from email-only routing") fired on 09-28; 09-15 (~89 min unnoticed) was the same risk class — a page that cannot reach a human — though its latency was missing *detection* (the keyword monitor was adopted 09-16), not email-only *delivery*.
- Recovery still requires a human in the loop even though the signature and its remedy (Management API restart) are proven twice — a page-then-approve loop still waits on a human who may be asleep.
- An earlier same-day window (10:34Z–10:37Z) fired and self-recovered unnoticed — the recurrence was visible only in retrospect from platform logs.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `No action items — incident fully resolved in the source PR with no residual work.` as a line of its own, with no emphasis — the permitted no-item form is plain so that the markdown linter (MD049, emphasis-style) cannot restyle it; the `/ship` gate accepts the plain line (and the underscore/asterisk-wrapped spellings shipped before this template changed).

| Issue | Action | Status |
|---|---|---|
| #9168 | Deliver the paging path: connect the native Better Stack→Slack integration (operator OAuth) and measure `push = true` on `app_health` at apply; deliver the bounded auto-restart watchdog (signature `{db,auth,rest} UNHEALTHY ∧ pooler ACTIVE_HEALTHY` sustained ≥3 reads + independent `/health` corroboration, `vars.WATCHDOG_ARMED` dark-launch, 30-min cooldown, audit issue, concurrency-group mutex); import the prd project into `supabase/supabase` Terraform pinned to `instance_size = "micro"` (Small flip is a follow-up); commit this postmortem, the ticket draft and ADR-260. | in PR #9184 |
| #9168 | Submit the committed Supabase support-ticket draft (`knowledge-base/engineering/operations/ticket-drafts/supabase-postgres-hang-recurring-2026-09.md`) via the dashboard — operator credential-entry step; no ticket API on Pro. | open (operator step) |
| #9168 | Better Stack Responder seat stays declined despite the `expenses.md` deferral trigger firing (twice): the $0 Slack path was chosen instead — revisit if Slack proves insufficient. Recorded in ADR-260 and `expenses.md`. | decided |
