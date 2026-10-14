---
title: "Supabase support ticket: recurring Postgres halt — prd project"
date: 2026-09-28
status: draft — operator submits via the Supabase dashboard (no ticket API on Pro)
project_ref: ifsccnjhymdmidffkzhl
project_name: soleur-web-platform
region: eu-west-1
issue: 9168
---

# Support ticket draft — recurring abrupt Postgres halt (submitted via dashboard)

Operator submission step for #9168: paste the body below into the Supabase
dashboard support form for project `ifsccnjhymdmidffkzhl`. Log excerpts are
minimized per GDPR Art. 5(1)(c) — deliberately no unbounded Postgres log
dumps; offer fuller extracts on request.

## Subject

Recurring abrupt Postgres halt on `soleur-web-platform` (ifsccnjhymdmidffkzhl) — two incidents in 13 days; restart recovers

## Body

**Project:** `ifsccnjhymdmidffkzhl` — `soleur-web-platform`, eu-west-1, Pro plan, Micro compute (no compute add-on selected — `GET /v1/projects/{ref}/billing/addons` shows only the custom-domain add-on).

**Summary.** The project's Postgres has now halted abruptly three times with an identical signature: the Postgres log stream stops mid-stream (no shutdown message, no error tail — logging simply ends), and the Management API health endpoint then reports `db`, `auth` and `rest` UNHEALTHY while `pooler` remains ACTIVE_HEALTHY. Only a project restart via the Management API recovers the instance — except in the second window below, which self-recovered.

**Windows (all UTC):**

1. **2026-09-15 ~14:16Z → 15:45Z** (~89 min). First occurrence. Edge returned HTTP 504 for every REST call; Management API reported `db`/`auth`/`rest`/`storage` UNHEALTHY while `pooler` and `realtime` stayed ACTIVE_HEALTHY; project status itself read ACTIVE_HEALTHY throughout. Recovered after `POST /v1/projects/ifsccnjhymdmidffkzhl/restart` at 15:39:06Z; postmaster restart logged 15:43:40Z; all services healthy 15:45:16Z. Post-restart config reload logged `configuration file ... contains errors; unaffected changes were applied` with `shared_buffers`/`max_connections` marked pending-restart.
2. **2026-09-28 10:34Z → 10:37Z** (~3 min). Same signature (db/auth/rest UNHEALTHY, pooler healthy); self-recovered without a restart. Noticed only in retrospect from platform logs.
3. **2026-09-28 ~16:12Z → 16:49Z** (~37 min). Same signature again. Restart issued ~16:43:32Z; services healthy ~16:48:49Z; application reconnected ~16:49:25Z.

**Minimized log excerpts** (summarized, not verbatim dumps — happy to provide fuller extracts on request):

- Postgres logs: normal activity stops mid-stream at onset in all three windows; no `FATAL`, no shutdown entry, no OOM signature visible to us before the halt. On 09-15, ~16 `canceling statement due to statement timeout` entries appear ~17 min after onset (queries piling up against a hung backend).
- Supavisor logs on 09-15: `DbHandler: Authentication timeout` while the pooler itself reported ACTIVE_HEALTHY.
- Post-restart (09-15): `received fast shutdown request`; postmaster start ~4 min after the restart POST; then the config-reload errors noted above.

**Checks already ruled out on our side:** no deploy, migration or infrastructure apply coincided with any onset window; the dev project on the same platform answered normally during the 09-15 window; the Supabase public status page showed no matching incident; database CPU/memory/connection metrics are not readable through the Management API available to us, and `pg_file_settings` is denied to the service role, so we cannot self-diagnose resource exhaustion.

**What we are asking:**

1. What fault class causes Postgres to halt abruptly — logs stopping mid-stream — while Supavisor stays healthy, on this project?
2. Is this correlated with the Micro compute class (memory pressure / cgroup kill below the Postgres log level)? Would the Small compute add-on plausibly eliminate it, or is this a platform-side fault that compute size cannot fix?
3. Do your internal platform logs/metrics for `ifsccnjhymdmidffkzhl` show a corresponding host- or cluster-side event at 2026-09-15 ~14:16Z, 2026-09-28 10:34Z, or 2026-09-28 ~16:12Z (no platform incident was posted)?
4. Why did the 10:34Z window self-recover in ~3 minutes while the other two held until a manual restart — is there an automatic recovery path that sometimes succeeds?
5. Anything we can collect next recurrence (metrics endpoints, flags) that would let us pinpoint the cause without a ticket round-trip?

**Impact:** production application outage for the duration of each window — sign-in and all data-backed requests fail while Postgres is down. We have since built monitoring + a bounded auto-restart watchdog on the Management API for this exact signature, but we need to know whether the underlying fault is ours to fix.
