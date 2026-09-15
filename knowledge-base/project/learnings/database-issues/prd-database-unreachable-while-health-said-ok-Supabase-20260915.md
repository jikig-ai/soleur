---
module: Supabase prd project / app health
date: 2026-09-15
problem_type: database_issue
component: database
symptoms:
  - "Supabase edge returned 504 for every REST call from 14:16:06Z"
  - "migrate job: Failed to connect to database: authentication did not complete within 15000ms"
  - "app /health returned HTTP 200 status ok with supabase: error"
  - "Management API project status ACTIVE_HEALTHY while /health?services= reported db/auth/rest/storage UNHEALTHY"
root_cause: missing_tooling
resolution_type: environment_setup
severity: high
tags: [supabase, postgres, health-check, alerting, incident, restart, management-api]
synced_to: [postmerge]
---

# Learning: prd database unreachable for 89 minutes while every health signal said "ok"

Post-mortem: `knowledge-base/engineering/operations/post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md`. Follow-up: #7884.

## Problem

The prd Supabase Postgres stopped serving at 14:16:06Z on 2026-09-15. PostgREST, auth and storage all failed, while the Supavisor pooler and realtime stayed up. Nobody was paged. The outage surfaced by accident, about 60 minutes in, when a docs-only PR's (#8207) deploy-arm `migrate` job hit a database authentication timeout.

## Investigation (what misled)

- **Treated the `migrate` failure as isolated.** The previous 7 deploy-arm runs were green and the diff was docs-only, so the failed jobs were rerun. The rerun's `migrate` then **succeeded via the pooler**, and `deploy` spent about 25 minutes looping on its health poll before anyone read `/health` directly. A green `migrate` is not evidence the database is up: the pooler path can succeed while Postgres-dependent services are down.
- **Project status lies by omission.** `GET /v1/projects/{ref}` read `ACTIVE_HEALTHY` throughout. Only `GET /v1/projects/{ref}/health?services=auth&services=rest&services=db&services=pooler&services=storage` showed `db` "Failed to connect to database".
- **`/health` is liveness, not readiness.** `buildHealthResponse()` hardcodes `status: "ok"` and HTTP 200; only the `supabase` field changes. The only monitor on it checks status code (#7884).

## Solution

Three read-only probes separated the hypotheses in about 10 minutes:

1. Direct REST probes to both the custom domain and the direct project host timed out, which rules out DNS or the custom domain.
2. The same probe against the dev project succeeded, which rules out a platform-wide incident.
3. `supabase-logs-query.sh` edge logs, bucketed per minute, pinned onset between 14:14:56Z and 14:16:06Z, before any change of ours.

Then an operator-approved `POST /v1/projects/{ref}/restart` fixed it. Recovery took about 6 minutes, with one flap. The sequence:

```bash
# readiness, not liveness
curl -sS https://app.soleur.ai/health | jq -r .supabase            # "error" while down
# service-level truth (project status alone says ACTIVE_HEALTHY)
curl -sS "https://api.supabase.com/v1/projects/$REF/health?services=db&services=auth&services=rest&services=pooler" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" | jq -c '[.[]|{name,status}]'
# onset from edge status codes (per-minute buckets)
doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --ref "$REF" --source edge_logs \
  --since <iso> --until <iso> --limit 1000 --json | jq -r '.sample[] | [.row_ts, (.event_message|split(" | ")[1])] | @tsv'
```

## Key Insight

For a managed database, **three different "healthy" signals can disagree, and the one that pages must be the service-level one.**

- App liveness (`status: ok`) and project status (`ACTIVE_HEALTHY`) both stayed green for 89 minutes.
- Pooler reachability (a green `migrate`) also said "up".
- Only the per-service health endpoint and the `/health` `supabase` field told the truth.

When a deploy's database step fails on an authentication timeout, read those two signals before rerunning.

## Session Errors

1. **The Phase 7 merge poll exited on a single transient `gh` fetch-error, twice.** Recovery: re-armed with a loop that tolerates up to 10 consecutive fetch errors. **Prevention:** the canonical poll block in `ship/SKILL.md` breaks on the first `fetch-error`. Harden it to count consecutive errors, together with its `merge-pr` mirror and fixture.
2. **The deploy-arm `migrate` failure was rerun before production database state was read.** Recovery: `/health` read and service probes about 16 minutes later. **Prevention:** `postmerge/SKILL.md` Production Debugging now says to read `/health` `.supabase` and Management API per-service health before rerunning a database-step failure.
3. **The filing gate rejected the follow-up issue three times.** First, a `;` right after the `--body-file` path defeated the gate's argument parse. Second, `Fix-Size` had no measured `N lines / M files`. Third, the measured size fell inside the inline threshold. Recovery: consolidated the alerting follow-up into existing #7884 and recorded the undetermined root cause as post-mortem evidence. **Prevention:** run each `gh issue create` alone, and write `Fix-Size:` as measured digits before filing.
4. **Management API log queries returned HTTP 429.** Recovery: narrower windows and fewer calls. **Prevention:** pace `supabase-logs-query.sh` calls. Its `CONFIG_ERROR` verdict on a 429 means rate-limited, not misconfigured.
5. **Two diagnostics were unavailable.** `psql` is not installed locally, and `pg_file_settings` is permission-denied for the Management API query role. Recovery: `pg_settings` through the Management API `database/query` endpoint. **Prevention:** none needed; use `pg_settings` + `pending_restart`.
