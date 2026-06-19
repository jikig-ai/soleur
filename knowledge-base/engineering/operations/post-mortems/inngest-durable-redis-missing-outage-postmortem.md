---
title: Inngest-server crash-loop — durable ExecStart live, inngest-redis never provisioned
date: 2026-06-18
brand_survival_threshold: single-user incident
gdpr_art33_notifiable: false
gdpr_art33_rationale: "Availability-only incident (inngest crons/reminders did not fire). No personal data was accessed, altered, disclosed, or lost — the Postgres/Redis backends contain queue/run-state, and no data store was breached."
gdpr_art34_high_risk_to_individuals: false
gdpr_art34_rationale: "n/a — availability outage, no personal-data exposure."
incident: "#5542"
status: resolved
---

# PIR: Inngest crash-loop — durable backend live without Redis

## Summary

On 2026-06-18, `inngest-server` on the prod Hetzner host crash-looped for ~3.5h (detected ~12:17 UTC, healthy as recently as 09:28 UTC). It was running the **durable-backend ExecStart** (`--postgres-uri --redis-uri`) but the host had **no Redis at all** — `inngest-redis.service` absent, no `redis-server` binary, no staged `/tmp/inngest-redis.*` assets — so it failed `dial tcp 127.0.0.1:6379: connect: connection refused` every ~9s. All crons + 4 armed reminders did not fire during the window.

## Detection

Found **incidentally** while verifying the #5542 cutover-capture bridge: `op=enumerate` returned an empty-body 500, then `op=inventory` returned `__FETCH_FAILED__` ("is inngest-server.service up?"). There was **no alert** — the gap that made this a multi-hour silent outage (see Action Items).

## Root cause

The durable backend's **Redis half was never provisioned on the host**. The durable ExecStart (from `inngest-bootstrap.sh`, #5459) was deployed, but `inngest-redis-bootstrap.sh` — which installs `redis-server` + the `inngest-redis.service` unit — only runs when the OCI image stages `/tmp/inngest-redis.{conf,service}`, and those assets were absent on the host even after deploying v1.1.15 (the redis-bearing tag). With no Redis listening on :6379, the durable inngest could not start. Compounding it: `verify_inngest_health` hard-requires the durable flags, so a SQLite-only rollback deploy "fails" verify and rolls back to the broken durable image — there was no fail-safe.

## Resolution

Recovered by running the canonical `inngest-redis-bootstrap.sh` (from the repo) over SSH against the host: installed `redis-server`, created `/mnt/data/redis`, installed + started `inngest-redis.service`, then restarted `inngest-server`. `op=inventory` → `functions=56` (healthy on Postgres + Redis). The durable cutover (#5450) is effectively complete on the current host.

## Impact

Availability only: inngest crons + reminders did not fire for ~3.5h. The `rebase-dependabot-5432` reminder (13:00) missed its window. No data loss/exposure. The 4 SQLite-era reminders did not migrate to the empty durable backend (re-arm tracked below).

## Action Items & Follow-ups

The **external inngest health watchdog** (`scheduled-inngest-health.yml`) is delivered in THIS PR — it closes the no-alert blind spot (the internal watchdog is an inngest cron and cannot detect inngest being down). Residual follow-ups:

| Issue | Action | Owner |
| --- | --- | --- |
| #5547 | Fix the durable image's redis-asset delivery + add a fail-safe so the durable ExecStart is not applied unless `inngest-redis` is verifiably up (else keep SQLite). | open |
| #5548 | Re-arm the reminders lost in the cutover (`verify-server-startup-rate-5417`, `reeval-5469-routine-runs-gate-2026-07-01`). | done — see below |

**#5548 re-arm (2026-06-18).** Re-armed `verify-server-startup-rate-5417` (fire 2026-06-19, `named-check` `sentry-issue-rate`) and `reeval-5469-routine-runs-gate-2026-07-01` (fire 2026-07-01, `issue-comment` to #5469) via `POST /api/internal/schedule-reminder` against the durable backend — **HTTP 202 ×2**. The `rebase-dependabot-5432-otel-2026-06-18` reminder was **not** re-armed: its fire window (13:00 2026-06-18) was already past, its body was never recorded (only inferred as `@dependabot rebase`), and it is outside this PIR's #5548 re-arm scope — `@dependabot rebase` can be commented directly on #5432 if the otel bump is still wanted. If inngest is DOWN during a future cutover, `op=capture` snapshots nothing, so survivors must be reconstructed from their source automations and re-armed this way.

## Lessons

- A self-monitoring watchdog hosted **inside** the monitored service has a blind spot for total-down — the monitor must be external (#5546).
- A backend cutover that depends on a sidecar (Redis) must hard-gate on the sidecar being live BEFORE switching the primary to depend on it, and fail safe to the prior backend otherwise (#5547).
