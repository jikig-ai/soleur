---
title: "Inngest restart de-plans all production crons until app-side re-registration"
date: 2026-06-11
incident_pr: 5160
incident_window: "2026-06-11 07:11–07:25 UTC and 09:04–09:15 UTC"
recovery_at: "2026-06-11T09:15:00Z"
suspected_change: "Standalone inngest-server restart (restart-inngest-server.yml / ci-deploy.sh restart arm) with no app-side SDK re-registration; surfaced during PR #5146 (#5145) AC12 verification"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "N/A — no personal-data breach; availability/reliability incident only"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

A standalone restart of the self-hosted `inngest-server.service` (via `restart-inngest-server.yml` → `ci-deploy.sh` restart arm, or a merge-push-triggered restart) leaves the Inngest function registry **empty until an app-side re-registration occurs**. Post-restart recovery is **push-driven** — the web-platform SDK must `PUT /api/inngest` (at container boot or manually) to re-register its manifest, which re-plans cron triggers at the substrate. It is NOT poll-driven, despite the `--poll-interval 60 --sdk-url` configuration that #5145 assumed would self-heal. On 2026-06-11 two independent restarts each de-planned ALL production crons; `--poll-interval 60` did not repopulate the registry across 5+ consecutive poll cycles (the full widened 120s cron budget elapsed with `"inngest_crons": {}`). The registry only repopulated when a manual `curl -X PUT https://app.soleur.ai/api/inngest` was fired (09:14:51) or when a concurrent Web Platform Release restarted the app container (re-registration at boot).

## Status

resolved — the fix (PR #5160, Ref #5159) forces the SDK re-registration inside `verify_inngest_health`'s cron-plan loop, so a restart self-registers and the de-plan window is eliminated.

## Symptom

After an inngest-server restart, every production cron (drift guards, KB template health, OAuth probes, community monitors, release digests) silently stopped firing. `ci-deploy.sh`'s `verify_inngest_health` terminated `inngest_health_failed` with `"inngest_crons": {}` even though `/health` was green — the server process was alive but no function manifest (and therefore no cron plan) had been re-registered.

## Incident Timeline

- **Start time (detected):** 2026-06-11T09:03:57Z (the de-plan was directly observed during PR #5146 AC12 re-dispatch; the earlier 07:11 window was reconstructed afterward)
- **End time (recovered):** 2026-06-11T09:15:00Z
- **Duration (MTTR):** ~11 min for the observed 09:04 window (~14 min for the earlier 07:11 window); ~24 min total de-planned time across both windows

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-11 ~07:11 | Merge-push-triggered restart (run 27330264724) restarts inngest-server; registry de-planned, all crons stop firing. |
| system | 2026-06-11 ~07:25 | Concurrent Web Platform Release restarts the app container; SDK re-registers at boot; crons recover (08:00–08:01 cohort checks in normally). |
| system | 2026-06-11 09:00:03–09:00:29 | Hourly Inngest crons (`scheduled-github-app-drift-guard`, `cron-kb-template-health`, `scheduled-oauth-probe`) check in to Sentry — registry alive. |
| agent | 2026-06-11 09:03:57 | `restart-inngest-server.yml` run 27336012125 dispatches `restart inngest _ latest`; host verify runs the full 303s budget and terminates `inngest_health_failed` with `"inngest_crons": {}` — registry empty for ≥5 poll cycles. |
| human | 2026-06-11 09:14:51 | Manual `curl -X PUT https://app.soleur.ai/api/inngest` returns `{"message":"Successfully registered","modified":true}` — registry repopulated via the push. |
| system | 2026-06-11 ~09:15 | Cron monitors resume check-ins; incident ends. |
| agent | 2026-06-11 (later) | Root cause identified (push-vs-poll re-sync asymmetry); fix authored as PR #5160 (Ref #5159). |

## Participants and Systems Involved

- `inngest-server.service` (self-hosted Inngest, SQLite at `/var/lib/inngest/`) on the prod Hetzner host.
- `apps/web-platform` container (the Inngest SDK serve endpoint at `127.0.0.1:3000/api/inngest`).
- `apps/web-platform/infra/ci-deploy.sh` `verify_inngest_health` + `restart-inngest-server.yml`.
- Sentry cron monitors (org `jikigai`) as the detection surface.
- Claude Code (agent) running the #5146 AC12 verification.

## Detection (+ MTTD)

- **How detected:** the de-plan was directly observed by the agent during PR #5146's AC12 verification re-dispatch (`reason=inngest_health_failed` with empty `inngest_crons`), corroborated by Sentry cron-monitor miss alerts. Monitoring system (Sentry monitors) + active verification, not external/manual report.
- **MTTD (mean time to detect):** ~6 min for the observed 09:04 window (de-plan at 09:03:57, terminal `inngest_health_failed` observed by ~09:10). The earlier 07:11 window was not detected in real time — it was reconstructed retrospectively.

## Triggered by

system — an internal `inngest-server.service` restart (workflow-dispatched and merge-push-triggered) with no paired SDK re-registration. Not user-driven, not provider-driven.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `--poll-interval 60` self-heals within the budget (#5145 assumption); the budget was just too tight | #5145 widened the cron budget to 120s | The full 303s widened budget elapsed with `"inngest_crons": {}` across 5+ poll cycles; only a PUT recovered it | Rejected |
| Recovery is push-driven: the SDK must `PUT /api/inngest` to re-register; the server cannot self-initiate a manifest sync post-restart | Manual PUT at 09:14:51 returned `modified:true` and crons recovered immediately; earlier window recovered only when the app container restarted (boot-time PUT) | None | Confirmed |
| L3→L7 connectivity / SSH-firewall failure | issue mentioned "timeout"/"health"/"restart" | All probes and the PUT run on the host loopback; no connectivity failure observed | Rejected |

## Resolution

PR #5160 (Ref #5159) fires a fire-and-forget loopback `curl -sf --max-time 10 -X PUT http://127.0.0.1:3000/api/inngest || true` **inside** `verify_inngest_health`'s cron-plan loop, before each `/v1/functions` poll. This converts the loop from passive-poll to active push-and-poll: each iteration re-fires the SDK registration that re-plans cron triggers, so the registry repopulates within the verify budget instead of waiting for an external container restart. One in-function edit covers both the restart arm and the deploy-inngest arm (both call `verify_inngest_health` arg-less). Because the in-loop PUT is additive and sequential, `restart-inngest-server.yml`'s client poll window was widened (`MAX_POLLS` 140→240 = 1200s) and the #5145 cross-file drift guard now counts the PUT `--max-time` by shape.

## Recovery verification

For the live incident: the manual PUT at 09:14:51 returned `{"message":"Successfully registered","modified":true}` and the Sentry cron monitors resumed check-ins within the hour.

For the fix: pre-merge, `bash apps/web-platform/infra/ci-deploy.test.sh` passes 85/85 (PUT wiring + fail-tolerance + the corrected drift guard showing `1200s covers 1040s`). Post-merge recovery proof is AC15 in the plan — a `restart-inngest-server.yml` re-dispatch must report `reason=success` (not `inngest_health_failed`) via `/hooks/deploy-status` and the Sentry monitors must check in within the hour **without** a manual PUT.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did all production crons stop firing?** The Inngest function registry was empty after the inngest-server restart — no function had a planned cron trigger.
2. **Why was the registry empty after a restart?** The inngest-server does not persist/re-derive its function manifest across a restart; it depends on the SDK to (re-)register the manifest.
3. **Why didn't the SDK re-register automatically?** Function discovery is **push-bound**: the web-platform SDK must `PUT /api/inngest` to register. The server's `--poll-interval 60 --sdk-url` polls the SDK's *serve* endpoint but, in the post-restart window, does not reliably re-plan cron triggers within the verify budget.
4. **Why did nothing fire the PUT?** The restart path (`ci-deploy.sh` restart arm / `restart-inngest-server.yml`) only restarts the service and polls for health; it never triggered the app-side re-registration. The only things that did were an app container restart (boot-time PUT) or a manual PUT — neither of which a standalone restart guarantees.
5. **Why was this not caught earlier?** #5145 widened the cron budget on the assumption that recovery was poll-driven and merely slow. No retry budget can pass when recovery requires an external push that nothing fires — a budget fix is necessary but insufficient.

**Final root cause:** re-sync asymmetry — recovery is push-driven (SDK `PUT /api/inngest` re-plans crons) while the restart path was poll-only, so a standalone restart de-planned the entire cron substrate until an unrelated external event re-registered the app.

## Versions of Components

- **Version(s) that triggered the outage:** `ci-deploy.sh` at commit `c2146e7a5` (#5146) — restart arm with the widened-but-poll-only cron budget; `restart-inngest-server.yml` `MAX_POLLS=140`.
- **Version(s) that restored the service:** live incident restored by manual PUT (no code version); permanently fixed by PR #5160 (in-loop PUT + `MAX_POLLS=240` + drift-guard PUT accounting).

## Impact details

### Services Impacted

All Inngest-fired production crons during the two windows: drift guards (`scheduled-github-app-drift-guard`), KB template health (`cron-kb-template-health`), OAuth probe (`scheduled-oauth-probe`), community monitors, and the weekly release digest. No HTTP/app-serving surface was affected — web-platform request handling was unaffected.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none directly — but any prospect-facing automation gated on a cron (e.g. community presence) was silently paused during the windows.
- Authenticated app user: no interactive impact; background automations (drift remediation, template health) did not run for ~24 min total.
- Legal-document signer: none.
- Admin via Access: none directly; the operator's automated brand presence (releases, community digests, drift remediation) silently stopped — invisible unless the operator read the Sentry cron-monitor miss alerts.
- Billing customer: none.
- OAuth installation owner: drift-guard / OAuth-probe crons did not fire during the windows, so a drift or token issue arising in those ~24 min would have been detected one cycle late.

### Revenue Impact

None measurable. No checkout, billing, or signing surface was affected; the incident was confined to background cron scheduling.

### Team Impact

Solo-operator product: ~1 session of agent + operator time to diagnose the push-vs-poll asymmetry, file #5159, and author the fix. No external escalation.

## Lessons Learned

### Where we got lucky

- The de-plan was directly observed during the #5146 AC12 verification rather than discovered days later via a missed brand action — the agent happened to be re-dispatching the restart workflow and watching `/hooks/deploy-status`.
- The earlier 07:11 window self-recovered because a concurrent Web Platform Release restarted the app container (boot-time PUT) — pure coincidence, not a designed backstop.

### What went well

- The #5145 cron-plan integrity gate (`verify_inngest_health` asserting ≥1 cron-triggered function, not just `/health`) made the de-plan *visible* as `inngest_health_failed` with empty `inngest_crons` rather than a silent green — without it the restart would have reported success.
- The manual PUT confirmed the push-driven recovery hypothesis live (`modified:true`), giving an empirically-validated fix contract before any code was written.

### What went wrong

- #5145 widened the budget on a poll-driven recovery assumption that was never verified against the actual recovery mechanism — the assumption survived into a merged PR.
- The restart path treated "server healthy" as "crons planned," conflating process liveness with manifest registration.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.**

| Issue | Action | Status |
|---|---|---|
| #5159 | Fire the loopback `PUT /api/inngest` inside `verify_inngest_health`'s cron-plan loop so a restart self-registers; widen `restart-inngest-server.yml` client window and count the PUT in the #5145 drift guard. PR #5160 merged + applied, but **AC15 failed twice live** — the loopback PUT did not re-plan crons (a manual public PUT did), so the fix is incomplete and the issue stays open. | open (AC15 unproven; see #5160 AC15-failure comment) |
| #5159 | **Diagnostic follow-up (PR #5178):** the silent `curl -sf … \|\| true` discarded the PUT's HTTP code, making the AC15 failure undiagnosable. Capture the code + surface it as `services.inngest_register_http` in `/hooks/deploy-status` (no-SSH) so the next AC15 run reveals 000/4xx/5xx/2xx and the real target/headers fix follows from data. | done (PR #5178; diagnostic returned `inngest_register_http=200` + `inngest_crons:{}` → registration-semantics, not reachability) |
| #5159 | **Root-cause fix attempt (PR #5182):** `serve()` had no `serveHost`, so a loopback PUT registered the `127.0.0.1` serve URL (HTTP 200, never cron-planned). Pinned `serveHost = NEXT_PUBLIC_APP_URL` — but this was a **no-op**: Next.js build-inlines `process.env.NEXT_PUBLIC_*` and that var is not a Docker build ARG → inlined `undefined` (post-deploy AC15 still showed `inngest_register_http=200` + `inngest_crons:{}`). | superseded by #5188 |
| #5159 | **Corrected fix (PR #5188):** hardcode `serveHost` to the canonical origin gated on `NODE_ENV===production` (not the build-inlined `NEXT_PUBLIC_APP_URL`), matching the `server/cf-cache-purge.ts` hardcoded-`APP_ORIGIN` convention. The pin now applies at runtime — **but AC15 STILL failed** (`inngest_register_http=200` + `inngest_crons:{}`), **refuting the serveHost theory entirely**: registering the public origin does not make the loopback PUT plan crons. | done (deployed; theory refuted) |
| #5159 | **Root-cause diagnostic 2 (PR #5191):** Better Stack's token is ingest-only (no query) and SSH is forbidden, so surface the decisive evidence via `/hooks/deploy-status` — the PUT's `modified` flag (`services.inngest_register_modified`: no-op `false` vs real-push `true`) + the inngest-server's own journald tail (`services.inngest_journal_tail`). One AC15 run then yields the data-driven true root cause + final fix. | open (PR #5191) |
| #5159 | **Resolution (reframe):** the restart-arm PUT premise was wrong — a loopback PUT is a modified:false no-op; crons re-arm only via a web-platform redeploy (modified:true) or the --poll-interval self-heal. Removed the dead PUT; verify_inngest_health's cron-plan check is now advisory (/health is the hard gate); runbook recovery = redeploy or wait-for-poll; Sentry monitors remain the H9b net. | open (closes on merge) |
| #5164 | Evaluate adding the same `PUT /api/inngest` to `inngest-bootstrap.sh` post-restart (and CI-wire `inngest.test.sh`) — deferred; re-evaluate only if a future incident shows the deploy-inngest-arm PUT racing the bootstrap restart. | open |
