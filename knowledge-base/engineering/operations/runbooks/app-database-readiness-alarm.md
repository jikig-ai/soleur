---
title: The app database readiness alarm fired
date: 2026-09-15
owners: engineering/ops
category: infrastructure
tags: [uptime, health, supabase, database, keyword-monitor, better-stack, readiness]
applies_to:
  - apps/web-platform/infra/uptime-alerts.tf
  - apps/web-platform/infra/variables.tf
  - apps/web-platform/server/health.ts
  - apps/web-platform/server/index.ts
related_issues: [7884]
---

# Runbook: the app database readiness alarm fired

**TL;DR:** run `curl -s --max-time 10 https://app.soleur.ai/health | jq -r .supabase`.
It needs no credentials. `connected` means the database is reachable from the app now and
the alarm is recovering or was a flap. `error` means the app cannot read Supabase: go to
[Diagnose](#diagnose). No output, or a `jq` parse error, means the app itself is not
answering: that is an app outage, and `soleur app dashboard` should be firing too.

## First: which alarm is this?

Three Better Stack monitors watch `app.soleur.ai` and `soleur.ai`. The email subject is the
only thing that tells them apart in an inbox.

| Alert name | URL | Means | Time to page |
|---|---|---|---|
| `soleur app database readiness` | `https://app.soleur.ai/health` | The `/health` body stopped containing `"supabase":"connected"`: the database is unreachable, the REST check took over 2 s, the service-role key was rejected, or the app is not answering at all. | ~6 min (up to 180 s to observe + 180 s confirmation) |
| `soleur app dashboard` | `https://app.soleur.ai/` | The app is unreachable, TLS-broken or erroring. | ~4 min (up to 180 s + 60 s confirmation) |
| `soleur dot ai apex` | `https://soleur.ai/` | The marketing site is unreachable. Unrelated to the database. | ~4 min (up to 180 s + 60 s confirmation) |

`soleur app database readiness` firing **alone** is the 2026-09-15 shape: the app is up, the
database is not. Firing together with `soleur app dashboard` means the app itself is down, and
the database may be fine.

## What is actually being asserted

`betteruptime_monitor.app_health` (`uptime-alerts.tf`) is a `keyword` monitor. It requests
`https://app.soleur.ai/health` and requires the exact substring `"supabase":"connected"` in the
body. Better Stack matches keywords case-insensitively.

`/health` answers HTTP 200 in every database state (`server/index.ts`). Only the body changes:
`buildHealthResponse()` in `server/health.ts` sets `supabase` to `connected` when a service-role
GET of `/rest/v1/users?select=id&limit=1` returns 2xx within 2 s, and to `error` otherwise. A
status-code monitor cannot see that, which is why the 2026-09-15 outage paged nobody for ~89
minutes ([post-mortem](../post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md)).

The keyword is compact JSON. A change to how `/health` serializes (pretty-printing, a renamed
field) breaks the match, and
`apps/web-platform/test/server/health-keyword-monitor-contract.test.ts` fails the PR before that
can merge. Rationale: [ADR-222](../../architecture/decisions/ADR-222-better-stack-database-readiness-pager-and-live-inventory.md).

## Diagnose

Every step below is a read. None needs SSH.

1. **Reproduce.** Read `/health` a few times, 20 s apart:

   ```bash
   for i in 1 2 3; do curl -s --max-time 10 https://app.soleur.ai/health | jq -c '{supabase, build_sha}'; sleep 20; done
   ```

   One `error` among `connected` reads is a flap; the 180 s confirmation window normally absorbs
   it. Repeated `error` is the real thing.

2. **Read the alarm's own state**, so you are not chasing a stale page. The token is the
   read-only one, sent as a header on stdin (never in curl's argv), with `--disable` and
   `--noproxy`:

   ```bash
   doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" \
     | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://uptime.betterstack.com/api/v2/monitors' \
     | jq -r '.data[] | select(.attributes.pronounceable_name=="soleur app database readiness")
              | .attributes | {status, monitor_type, required_keyword, paused, last_checked_at}'
   ```

   `monitor_type` must read `keyword` and `required_keyword` must read `"supabase":"connected"`.
   If either differs, or `paused` is `true`, the alarm was edited on the vendor side; the
   twice-daily reconcile reports this as `reason=monitor-config-drift`.

3. **Control probe: is it this project, or Supabase at large?** Run the same REST read the app
   runs, against prd and against dev. Each prints only the HTTP code and the time:

   ```bash
   for cfg in prd dev; do
     printf '%s: ' "$cfg"
     doppler run -p soleur -c "$cfg" -- bash -c 'printf "apikey: %s\nAuthorization: Bearer %s\n" "$SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_SERVICE_ROLE_KEY" \
       | curl --disable --noproxy "*" -sS -o /dev/null --max-time 10 -w "%{http_code} %{time_total}s\n" --header @- \
         "$SUPABASE_URL/rest/v1/users?select=id&limit=1"'
   done
   ```

   | prd | dev | Reading |
   |---|---|---|
   | `000` / timeout / `5xx` | `200` | A project-local database fault (the 2026-09-15 shape). Go to step 4. |
   | `000` / timeout / `5xx` | also failing | Platform-wide or network. Check the Supabase status page, and read step 4 anyway. |
   | `401` | `200` | The service-role key is rejected. Go to [The service-role key cause](#the-service-role-key-cause). |
   | `200` quickly | `200` | Doppler's key and the database both work from here. If `/health` still says `error`, the running container holds a different key or URL than Doppler, or its reads exceed 2 s. |

4. **Per-service health from the Management API.** Project status alone read `ACTIVE_HEALTHY`
   for the whole 2026-09-15 outage; only the per-service endpoint showed `db` failing:

   ```bash
   REF=ifsccnjhymdmidffkzhl   # soleur-web-platform (prd application project)
   doppler run -p soleur -c prd -- bash -c 'printf "Authorization: Bearer %s\n" "$SUPABASE_ACCESS_TOKEN" \
     | curl --disable --noproxy "*" -sS --max-time 30 --header @- \
       "https://api.supabase.com/v1/projects/'"$REF"'/health?services=db&services=auth&services=rest&services=pooler&services=storage"' \
     | jq -c '[.[] | {name, status}]'
   ```

   `db`, `auth`, `rest` and `storage` unhealthy while `pooler` stays healthy is the 2026-09-15
   pattern. A green `pooler` (or a green `migrate` job, which goes through the pooler) is not
   evidence that Postgres is serving.

5. **Onset and cause from platform logs**, through `scripts/supabase-logs-query.sh`
   ([supabase-log-query.md](supabase-log-query.md) has every flag):

   ```bash
   doppler run -p soleur -c prd -- \
     scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl --source postgres_logs --since 2h
   doppler run -p soleur -c prd -- \
     scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl --source edge_logs --since 2h --json
   ```

   Look for statement timeouts, authentication timeouts and the first 5xx at the edge. The
   Management API rate-limits log queries; a `CONFIG_ERROR` verdict right after a 429 means
   "slow down", not "misconfigured".

### The service-role key cause

A `401` from the prd REST read in step 3 means `SUPABASE_SERVICE_ROLE_KEY` in Doppler `prd` no
longer matches the project's API keys, so `/health` reports `error` while the database is
healthy. Server-side reads that use that key fail as well.

There is no dedicated rotation runbook for the service-role key.
[supabase-db-credential-rotation.md](supabase-db-credential-rotation.md) covers the adjacent
credential, the Postgres password in the Doppler connection strings, and is the right runbook
only when those strings are what failed (a `migrate` job failing authentication, for example).
Correcting the service-role key is a production secret write. The container receives Doppler `prd`
values at deploy time (`ci-deploy.sh` downloads them into its env-file), so a corrected value also
needs a deploy. Both need explicit operator authorization, as below.

## Remediate

**A project restart is a production write.** On 2026-09-15 the database recovered only after a
Management API `POST /v1/projects/{ref}/restart` (about 6 minutes to healthy, with one flap).
Do not issue it on the strength of this runbook or of a menu choice: it needs the operator's
explicit authorization for that specific write (`hr-menu-option-ack-not-prod-write-auth`).
Present the step 3 and step 4 readings, the options (watch, restart, hands-off) and the expected
recovery time, and wait for a clear go-ahead.

After any remediation, confirm recovery with the TL;DR read on three reads 20 s apart and with
step 4 showing every service healthy. The Better Stack incident closes by itself after
`recovery_period` (180 s) of passing checks.

## The monitor itself is gone: the import off-switch

`betteruptime_monitor.app_health` adopted the hand-made monitor `4226366` through an `import {}`
block in `uptime-alerts.tf`, gated by `var.adopt_app_health_monitor` (default `true`). If that
monitor is deleted on the vendor side, Terraform drops it from state and most likely re-attempts
the import on every plan, and the import of a missing id aborts the plan for the whole
`apps/web-platform/infra` root. This is derived from Terraform source, not measured (ADR-222).

Signals, all automated:

- The next reconcile run files or updates the `heartbeat-reconcile-mismatch` issue with
  `surface=monitors reason=absent-live resource=betteruptime_monitor.app_health`.
- The next infra merge's `apply-web-platform-infra.yml` run fails in its apply step, and its
  `notify-apply-failure` job emails ops.

Remedy, done as an ordinary PR (an agent can carry it end to end with `/soleur:one-shot`):

1. **Confirm the deletion by id, read-only.** A `404` confirms it; anything else means the
   failure has another cause, so stop here:

   ```bash
   doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" \
     | curl --disable --noproxy "*" -sS -o /dev/null -w "%{http_code}\n" --max-time 30 --header @- \
       https://uptime.betterstack.com/api/v2/monitors/4226366'
   ```

2. **Confirm the apply failure names the import.**

   ```bash
   gh run list --workflow=apply-web-platform-infra.yml -L 5
   gh run view <run-id> --log-failed | grep -iE 'import|4226366|app_health'
   ```

3. **Open a PR that sets `default = false`** on `variable "adopt_app_health_monitor"` in
   `apps/web-platform/infra/variables.tf`. Leave the `import {}` block and the `resource` in
   place. The tftest already sets the variable to `false`, so no test changes.

4. **Merge it.** `apply-web-platform-infra.yml` then plans a create of
   `betteruptime_monitor.app_health` with the declared keyword configuration, under a new id. The
   old check history is lost with the deleted monitor.

5. **Verify.** Step 2 of [Diagnose](#diagnose) shows the monitor with `monitor_type` `keyword`
   and `status` `up`. The next reconcile run prints `SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors`
   with the new id in `matched=`.

Removing the import block and the variable altogether is tracked as a follow-up to #7884, once
the post-merge read-back of the adoption passes.

## What this alarm does NOT cover

- **A Better Stack outage.** Database readiness has no second alarm; no Sentry assertion reads
  the `/health` body.
- **web-2.** `app.soleur.ai` resolves to web-1 alone (`cloudflare_record.app` in `dns.tf`), so
  the probe sees only web-1's view of Supabase.
- **Slowness below 2 s**, and database faults that leave a one-row `users` read working.
- **Email latency.** Paging is email only, so the time to act includes reading the inbox.

## Related

- [ADR-222](../../architecture/decisions/ADR-222-better-stack-database-readiness-pager-and-live-inventory.md): why the alarm reads the body, and the declared-or-reported rule for live Better Stack objects
- [ADR-204](../../architecture/decisions/ADR-204-redirect-health-moves-to-better-stack-because-sentry-cannot-express-it.md): where monitor 4226366 was first found unmanaged
- [Post-mortem: prd Supabase database unreachable, 2026-09-15](../post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md)
- [www-redirect-alarm.md](www-redirect-alarm.md): the sibling Better Stack alarm runbook
- Issue [#7884](https://github.com/jikig-ai/soleur/issues/7884)
