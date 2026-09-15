---
title: "prd Supabase database unreachable 2026-09-15"
date: 2026-09-15
incident_pr: 8215
incident_window: "2026-09-15T14:16:06Z → 2026-09-15T15:45:16Z"
recovery_at: "2026-09-15T15:45:16Z"
suspected_change: "None identified. No deploy, migration or infra apply ran in the onset window. PR #8207 (a legal-doc change with no database or infra surface) merged mid-incident and its deploy-arm migrate job surfaced the outage."
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

The production Supabase project's Postgres became unreachable for about 1h29m, so sign-in and every data-backed page of app.soleur.ai failed. The project's own status stayed "healthy" and no monitor paged. The outage was found by accident, during PR #8207's post-merge verification, and cleared by an operator-approved project restart. The root cause is platform-side and not yet determined.

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

- The Supabase edge returned HTTP 504 for every sampled REST call from 14:16:06Z. The last successful call was at 14:14:56Z.
- The Web Platform Release deploy-arm `migrate` job failed at 15:16:10Z with `Failed to connect to database: authentication did not complete within 15000ms`.
- app.soleur.ai `/health` returned `status: ok` with `supabase: error`.
- The Management API health endpoint reported `db` "Failed to connect to database" and `auth`, `rest` and `storage` UNHEALTHY, while `pooler` and `realtime` stayed ACTIVE_HEALTHY and the project status read ACTIVE_HEALTHY.
- The dev project on the same platform answered normally, and the Supabase public status page showed no matching incident.

## Incident Timeline

- **Start time (detected):** 2026-09-15T14:16:06Z
- **End time (recovered):** 2026-09-15T15:45:16Z
- **Duration (MTTR):** 1h29m

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 14:14:56Z | Last HTTP 200 at the Supabase edge (reconstructed from edge logs after the fact). |
| agent | 14:16:06Z | First HTTP 504 at the Supabase edge. Every sampled REST call returns 504 from here on. Incident start. |
| agent | ~14:33Z | 16 `canceling statement due to statement timeout` entries in Postgres logs. |
| agent | 14:51Z | PR #8207 (AUP legal-doc change, no database or infra surface) auto-merges via the ship pipeline. |
| agent | 15:16:10Z | Deploy-arm `migrate` job for the #8207 merge commit fails on a database authentication timeout. First signal anyone saw. |
| agent | 15:16:28Z | Supavisor logs `DbHandler: Authentication timeout`. |
| agent | 15:17Z | Agent reruns the failed release jobs (isolated failure; the previous 7 deploy-arm runs were green). `migrate` succeeds via the pooler; `deploy` starts and loops on health verification. |
| agent | 15:33Z | Agent reads `/health`: `supabase: error` on 4 consecutive reads. |
| agent | 15:36Z | Read-only probes: the custom API domain and the direct project host both time out; the dev project responds in 0.17s. |
| agent | 15:37Z | Management API health: `db`, `auth`, `rest`, `storage` UNHEALTHY; `pooler`, `realtime` healthy; no database upgrade in progress. |
| agent | 15:38Z | Operator notified by push notification and asked to choose a remedy (watch, restart, or hands-off). |
| agent-with-ack | 15:39:06Z | Operator chose restart. Management API `POST /restart` returns 200 and the project goes to RESTARTING. |
| agent | 15:41:57Z | Postgres `received fast shutdown request`; connections terminated by administrator command. |
| agent | 15:43:40Z | Postmaster starts. |
| agent | 15:44:17Z | The rerun's deploy health poll reads `supabase: connected` for the first time. |
| agent | 15:44:27Z | Postgres reloads config: `configuration file ... contains errors; unaffected changes were applied`. Several tuning parameters reset to default; `shared_buffers`, `max_connections` and three others marked as needing a restart. |
| agent | 15:44:44Z | One flap: `auth` and `rest` briefly UNHEALTHY, `/health` `supabase: error`. |
| agent | 15:45:04Z | Deploy-arm rerun concludes: `deploy` and `live-verify` success (live-verify finished 15:44:53Z); prod runs 2ff3e1592. |
| agent | 15:45:16Z | All services ACTIVE_HEALTHY; `/health` `supabase: connected`. Recovered. |
| agent | 15:46:52Z | `/health` `supabase: connected` on 3 further reads 20s apart. |

## Participants and Systems Involved

- Operator (single founder), who approved the restart.
- Claude Code session running the #7981 one-shot pipeline (ship/postmerge).
- Supabase prd project (eu-west-1): Postgres, PostgREST, GoTrue auth, Storage, Supavisor pooler, Realtime.
- Web Platform Release workflow (deploy arm).
- Better Stack uptime monitors and Sentry, which did not alert.

## Detection (+ MTTD)

- **How detected:** manual — monitoring system vs. external/manual report. Found by accident while investigating a failed `migrate` job in #8207's post-merge release verification, not by an alert.
- **MTTD (mean time to detect):** Unknown (external/manual report). The first human-visible signal (the failed `migrate` job, 15:16:10Z) came about 60 minutes after onset, and diagnosis was confirmed at 15:37Z.

## Triggered by

provider — one of user / system / market movement / provider.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| A change we shipped (deploy, migration, infra apply) broke the database | #8207 merged during the window | Onset (14:16Z) predates #8207's merge (14:51Z); #8207 touched no database, migration or infra surface; no non-PR workflow that touches Supabase ran between 13:55Z and 14:20Z; the dev project was unaffected | Rejected |
| Custom-domain or DNS / edge routing failure | 504s at the edge; `/health` targets the custom API domain | The direct project host timed out identically; the pooler and realtime were healthy | Rejected |
| Supabase platform-wide incident | Platform-side symptoms | Public status page showed no matching incident; the dev project on the same platform was healthy | Rejected as platform-wide; project-local platform fault remains open |
| Project-local Postgres hang or resource exhaustion (memory, connections) on the default compute (no compute add-on selected) | Statement timeouts before the outage; auth/rest/storage (all Postgres-dependent) down while the pooler process stayed up; a restart cleared it; the post-restart config reload reported errors and pending-restart memory and connection parameters | No compute or memory metrics were readable through the available API; `pg_file_settings` access is denied to the service role | Open — most likely, unconfirmed |

## Resolution

With operator approval, the project was restarted through the Supabase Management API at 15:39:06Z. Postgres shut down, came back up, and all services reported healthy from 15:45:16Z after one brief flap. The stalled deploy-arm run for #8207 was rerun; it passed `deploy` and `live-verify` once the database recovered.

## Recovery verification

- Management API health: `auth`, `rest`, `db`, `storage` ACTIVE_HEALTHY on two consecutive reads (15:45:16Z, 15:45:48Z).
- app.soleur.ai `/health`: `status: ok`, `supabase: connected`, `build_sha` 2ff3e1592 on reads at 15:46:11Z, 15:46:31Z and 15:46:52Z.
- Web Platform Release deploy-arm run 34987199544, attempt 2: `migrate`, `deploy` and `live-verify` all success.
- Postgres `pg_postmaster_start_time()` = 15:43:40Z, with 14 active connections at about 15:55Z.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was the app down?** PostgREST, GoTrue and Storage could not reach Postgres, so every data-backed request returned 504.
2. **Why could they not reach Postgres?** The project's Postgres instance stopped accepting or completing connections at about 14:16Z (Management API: `db` "Failed to connect to database"), while the separate Supavisor pooler process stayed up.
3. **Why did Postgres stop serving?** Undetermined. The evidence points to a project-local platform fault on the default compute: statement timeouts beforehand, recovery by restart alone, and a post-restart config reload that reported errors and left `shared_buffers`/`max_connections` pending a restart. No change on our side coincides with the onset.
4. **Why did it last about 90 minutes?** Nothing alerted. `/health` returns HTTP 200 with `status: ok` whatever the database state, and the Better Stack monitor on it checks the status code only (#7884). The Terraform-managed monitors check page status only.
5. **Why does no monitor read database state?** The health contract was designed for deploy liveness, not dependency readiness. The `supabase` field is consumed by the release workflow's health poll and by nothing that pages.

Final root cause: **platform-side Postgres unavailability (cause undetermined), prolonged to about 90 minutes by a missing database-readiness alert.** The alerting gap is tracked in #7884. The undetermined platform cause has no in-repo fix and is recorded here as evidence. Another occurrence now pages once #7884 lands.

## Versions of Components

- **Version(s) that triggered the outage:** None on our side. Prod was running web-platform 0.274.x; no deploy, migration or infra apply coincided with the 14:16Z onset.
- **Version(s) that restored the service:** No code change. Supabase project restart at 15:39:06Z; web-platform v0.274.4 at 2ff3e1592 was deployed after recovery.

## Impact details

### Services Impacted

app.soleur.ai sign-in (Supabase auth), every data-backed page and API route (PostgREST), file storage, server-side jobs that read or write Postgres (routine runs, stuck-conversation reaper, GitHub webhook event recording), and the Web Platform Release deploy chain. The marketing site soleur.ai was unaffected.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: unaffected — soleur.ai returned 200 throughout.
- Authenticated app user: could not sign in or load conversations, workspaces or KB data for about 89 minutes. No data loss was observed.
- Legal-document signer: T&C acceptance writes would have failed during the window; no evidence of a partial write.
- Admin via Access: no admin surface depends on this path; not affected.
- Billing customer: billing pages that read Postgres would have failed. No payment-provider writes are known to have been lost. Unverified.
- OAuth installation owner: GitHub webhook event recording (`processed_github_events`) returned 504; whether GitHub redelivered those events is unverified.

### Revenue Impact

Unknown / N/A

### Team Impact

About 45 minutes of the operator session diverted from the #7981 ship pipeline to diagnosis and recovery.

## Lessons Learned

### Where we got lucky

A legal-doc PR with no database surface happened to merge during the outage, and its deploy chain happened to need the database. Without that, nothing in the system would have surfaced the outage.

### What went well

- Diagnosis used only no-SSH reads: `/health`, direct REST probes against both hosts, a control probe of the dev project, Management API health, Supabase platform logs through `scripts/supabase-logs-query.sh`, and read-only `pg_settings`. It separated our change, the custom domain, and a platform-wide incident from a project-local fault in about 10 minutes.
- The production write (restart) was taken only after an explicit operator menu choice.
- The edge logs pinned the onset to a 70-second window (14:14:56Z–14:16:06Z), so our deploys were ruled out mechanically, not by argument.

### What went wrong

- No alert fired for about 90 minutes. `/health` answers `status: ok` with HTTP 200 when the database is down, and every uptime monitor checks status only (#7884).
- Sentry was receiving app-side symptoms (`WEB-PLATFORM-4G` workspaces read errors, reaper silent fallbacks), but those issues had been recurring for a day without alert rules, so the outage was indistinguishable from background noise.
- The first reaction to the `migrate` failure was to treat it as isolated and rerun it. That was correct as a first move, but its health poll then looped from 15:22Z, and `/health` was not read directly until 15:33Z (about 16 minutes after the rerun; the poll itself kept looping about 22 minutes until recovery), before anyone read `/health` directly.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `No action items — incident fully resolved in the source PR with no residual work.` as a line of its own, with no emphasis — the permitted no-item form is plain so that the markdown linter (MD049, emphasis-style) cannot restyle it; the `/ship` gate accepts the plain line (and the underscore/asterisk-wrapped spellings shipped before this template changed).

| Issue | Action | Status |
|---|---|---|
| #7884 | Bring the `app.soleur.ai/health` Better Stack monitor under Terraform and make database unavailability page: a required keyword `"supabase":"connected"` or a sibling readiness monitor. Scope widened and raised to p1 on 2026-09-15 for this incident. | open |
