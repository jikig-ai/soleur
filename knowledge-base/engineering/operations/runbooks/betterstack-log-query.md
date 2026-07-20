# Runbook: Querying Better Stack logs (historical, programmatic)

**TL;DR:** Use [`scripts/betterstack-query.sh`](../../../../../scripts/betterstack-query.sh) under `doppler run -p soleur -c prd_terraform`. It queries the ClickHouse HTTP SQL API. The ingest token is write-only; reading historical logs needs a dedicated ClickHouse *connection* (already provisioned — creds in Doppler).

```bash
# Last 1h of app logs mentioning a cron, excluding host-metric noise:
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 1h --grep cron-roadmap-review --raw-only --limit 50

# Arbitrary SQL (write the literal token $BS_TABLE for the remote() arg):
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh \
  'SELECT count() AS n FROM remote($BS_TABLE) WHERE dt >= now() - INTERVAL 2 HOUR FORMAT JSONEachRow'
```

## Standing alarms over this source (log-content recurrence alarms)

A **log-*content* recurrence alarm** over this Better Stack Logs source is an **in-repo GitHub-Actions
cron poller**, NOT a native Better Stack alert — query via `betterstack-query.sh` → decode/threshold
in a `scripts/` checker → deduped `action-required` GitHub issue → Sentry self-liveness heartbeat.
This is the reusable **"Pattern: Better Stack log-content alarms"** recorded in
[`ADR-096` §Consequences](../../architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md)
(the `better-uptime` TF provider has no log-alert resource, and the Telemetry v2 SQL-alert API is
rejected for stateful/newest-scoped signals + the operator-surface reasons documented there).

Live standing alarms over this source:

- **`scheduled-zot-restart-loop.yml`** (#6291, every 30 min) — the zot registry restart-loop
  recurrence alarm. Reads the `SOLEUR_ZOT_DISK` marker, fires a deduped `[ci/zot-restart-loop]`
  issue on a newest-`boot_id` OOM/crash-loop and a `[ci/zot-telemetry-silent]` issue if the
  reporter goes dark. Checker: `scripts/zot-restart-loop-alarm.sh` (shared parse helper
  `scripts/lib/zot-telemetry-parse.sh`); self-liveness `sentry_cron_monitor.zot_restart_loop_alarm`.
  Dry-run: `doppler run -p soleur -c prd_terraform -- bash scripts/zot-restart-loop-alarm.sh`.
  - **Also reads `SOLEUR_PRIVATE_NIC`** (#6415 / ADR-115) — the registry host's own assertion
    that its private IP (`10.0.1.30`) is configured. Carried as an **independent** verdict
    (`NIC_ALARM_VERDICT`, deliberately NOT in the exit code) and firing three deduped
    `[ci/registry-private-nic]` classes: *host has no private NIC* (terminal),
    *boot race self-healed* (advisory — a successful heal emits `nic_ok=true`, so the terminal
    branch structurally cannot see it), and *guard went dark* (absence).
    Query: `… --grep SOLEUR_PRIVATE_NIC`. Decode: `imds_rc!=0` → H1 (metadata-service blip);
    `imds_rc=0 && imds_nets=0` → H2 (the `hcloud_server_network` additive online-attach race);
    `imds_nets>0 && converged_by!=already` → the attach landed and the guest never configured it.
    **If zot is reported unreachable, rule the private NIC out FIRST** — #6400 was 14 days of
    "zot mysteriously down" that was actually a missing NIC, and a NIC-less host keeps public
    egress so every other signal here stays green.
- **`scheduled-followthrough-sweeper.yml`** — one-shot soak follow-throughs (e.g.
  `scripts/followthroughs/zot-restart-plateau-6288.sh`) recur the same query+decode shape.

## ⚠️ A "no creds" / TRANSIENT error is NOT "no access" (repeat misdiagnosis)

`betterstack-query.sh` does **not** read Doppler itself — it needs the query creds
**injected** via `doppler run`. Run it in a bare shell and it exits with
`BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not set`; a follow-through that wraps it
(e.g. `chardevice-wedge-nonrecurrence-5934.sh`) then reports `TRANSIENT: … auth/config/network`.

**Neither means this session lacks Better Stack access.** Both mean the call was not
wrapped in `doppler run`. The fix is always the same — re-run:

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh <args>
```

Do NOT conclude "I can't verify from here" and stop. This mistake has now happened
twice (the note below, and #5934); the script's error message itself now spells out
the correct invocation. See hard rule `hr-verify-repo-capability-claim-before-assert`
— a fail-safe/degraded probe output is *inconclusive*, never proof of a capability gap.

## Why this exists (the three-token trap)

Better Stack has **three** distinct credentials and it is easy to reach for the
wrong one (we initially skipped log-querying believing we lacked access — we did
not):

| Credential (Doppler `soleur`) | Scope | Use for |
|---|---|---|
| `BETTERSTACK_LOGS_TOKEN` (`prd`) | **ingest only** (write) | Vector → Better Stack shipping. CANNOT read. |
| `BETTERSTACK_API_TOKEN` (`prd_terraform`) | Telemetry mgmt API | sources, **connections**, metadata. NOT log content. |
| `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` (`prd_terraform`) | ClickHouse HTTP read | **reading historical logs/metrics via SQL** |

The query creds are a ClickHouse HTTP *connection* — a username/password pair
Basic-auth'd against a regional ClickHouse endpoint, separate from both tokens.

## Connection details (provisioned 2026-06-01)

- Source: `soleur-inngest-vector-prd` — id **2457081**, team **520508**, table_name `soleur_inngest_vector_prd_3`, region `eu-fsn-3`, **3-day log retention**.
- Query host: `eu-fsn-3-connect.betterstackdata.com:443` (region-scoped — creds fail against other clusters).
- `remote()` table identifier: **`t<TEAM_ID>_<table_name>_logs`** → `t520508_soleur_inngest_vector_prd_3_logs`. The docs' `t123456_...` placeholder is the **team id**, not the source id. (Suffixes: `_logs`, `_metrics`, `_spans`.)

## Re-minting the query connection (if creds are lost/rotated)

Fully automated via the Telemetry API — **no dashboard click-path needed**:

```bash
TOK=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)
curl -sS -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
  --data '{"client_type":"clickhouse","team_ids":[520508]}' \
  https://logs.betterstack.com/api/v1/connections
# → 201 {data:{attributes:{host,port,username,password,data_region}}}
```

Then store (never echo the password):

```bash
doppler secrets set BETTERSTACK_QUERY_HOST=<host>     -p soleur -c prd_terraform --no-interactive
doppler secrets set BETTERSTACK_QUERY_USERNAME=<user> -p soleur -c prd_terraform --no-interactive
printf '%s' "<password>" | doppler secrets set BETTERSTACK_QUERY_PASSWORD -p soleur -c prd_terraform --no-interactive
```

List existing connections: `GET https://logs.betterstack.com/api/v1/connections` (Bearer `BETTERSTACK_API_TOKEN`).

## Query mechanics

- Endpoint: `POST https://$BETTERSTACK_QUERY_HOST?output_format_pretty_row_numbers=0`, Basic auth, body = SQL, `Content-type: plain/text`.
- Always end SELECTs with `FORMAT JSONEachRow` for line-delimited JSON.
- Columns: `dt` (event time, use for WHERE/ORDER), `raw` (the full log line as text/JSON).
- Recent logs: `remote(t520508_..._logs)`. Older than the hot window: `s3Cluster(primary, t520508_..._s3)` with `WHERE _row_type = 1`, `UNION ALL`-combined.

## App container pino lines (cron failures) — now queryable (#4773, 2026-06-02)

**Closed (was a coverage gap discovered 2026-06-01).** The Next.js app container's
pino stdout — including `spawnClaudeEval` cron output, `fn: cron-<name>` — now
ships to this source. The container starts with `--log-driver journald`
(cloud-init.yml + ci-deploy.sh, all 3 `docker run` sites), and Vector's
`app_container_journald` source ingests it filtered to pino **WARN+** (level ≥ 40)
via `app_container_warn_filter`, then through the same 3-stage `pii_scrub_*`
redaction as every other source.

Query cron pino lines in Better Stack by `source_kind`:

```sql
SELECT dt, raw FROM remote(t520508_..._logs)
WHERE raw LIKE '%"source_kind":"app_container"%'
  AND raw LIKE '%"fn":"cron-growth-audit"%'
ORDER BY dt DESC LIMIT 50 FORMAT JSONEachRow
```

Two deliberate trade-offs:
- **WARN+ only.** The filter parses the pino `level` field (NOT journald
  `PRIORITY` — Docker's journald driver maps all stdout to PRIORITY 6 regardless
  of pino level, so a PRIORITY filter would drop everything). INFO/DEBUG (the
  request-log firehose) is dropped for quota. A non-zero claude exit logs at
  error level → shipped. The INFO-level `claude --print` **max-turns notice**
  is NOT here — it reaches **Sentry** via the `scheduled-output-missing`
  `extra.stdoutTail` (#4773 PR-A), alongside `extra.stderrTail`/`extra.exitCode`.
- **Container log retention moved to journald.** Switching off `json-file`
  dropped its `max-size 10m/max-file 3` rotation; the container's `docker logs`
  and retention are now governed by journald — at its **default** `SystemMaxUse`
  (min(10% of /var, 4 GB)) unless an explicit bound is provisioned. Explicitly
  sizing `SystemMaxUse` + ensuring `Storage=persistent` (so the journal survives
  reboot and the redirected container volume can't evict the supervisor/system
  journal Sources 1/2 depend on) is tracked as a follow-up infra task — the
  journald storage config predates #4773 and applies equally to the two
  pre-existing journald sources.
- **Rollout on existing hosts (non-load-bearing order).** PR-C is fully active
  only after BOTH (a) an inngest-bootstrap deploy ships the new `vector.toml`,
  AND (b) a web-platform deploy re-creates the `soleur-web-platform` container
  with `--log-driver journald`. Either interleaving degrades gracefully: a
  journald source with no matching lines is benign, and a journald-logging
  container with no matching source just isn't shipped until the config lands.
  No operator action beyond a normal deploy of both components.

## Querying Anthropic cost markers (`SOLEUR_CLAUDE_COST` / `_DAILY`)

The production Claude fleet emits two structured cost-marker families at pino
**WARN** (so the same `app_container_warn_filter` ships them). Both ride the
existing app-container → journald → Vector → Better Stack path — **no
`betterstack-query.sh` change**; the `--grep` form already does `raw LIKE '%…%'`:

```bash
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 48h --grep SOLEUR_CLAUDE_COST --limit 20
```

- **`SOLEUR_CLAUDE_COST`** — per-turn (sessions) + per-run (crons). Emitted from
  the `cost-writer` choke point (`source ∈ {agent-runner, cc-soleur-go,
  leader-loop}`), the `spawnClaudeEval` substrate (`source: "cron:<name>"`,
  `capture_status ∈ {ok, no-result-event, parse-error, timeout}`), and the
  `postAnthropicMessage` HTTP transport (`cron:<name>`, tokens-only). A
  `capture_status != "ok"` row is a *shipped* capture-failure event — NOT
  row-absence — so "capture broke" is distinguishable from "genuinely \$0".
- **`SOLEUR_CLAUDE_COST_DAILY`** — the once-a-day Admin cost-report cron
  (`cron-anthropic-cost-report`), carrying the org-total `cost_usd` + a per-model
  array. A `{status:"key-missing"}` row is the correct **dark** signal while
  `ANTHROPIC_ADMIN_KEY` is unprovisioned (do NOT triage its absence as a
  regression during the mint window).
  - **`days_since_first_dark`** — whole UTC days since the *first observed* dark
    fire (2026-07-10), present on `key-missing` rows only. It is **not** the age
    of the current dark window: it never resets, so after a mint-then-rotate it
    reads the full elapsed span on day one of a benign gap. Read it as "how long
    has this surface been unprovisioned at least once", never as "how long has it
    been broken right now". Nothing branches on it.
  - **Absent-vs-zero trap.** The field is *omitted* on `status:"ok"` rows, and
    `JSONExtractInt(raw,'days_since_first_dark')` returns **0** for a missing key.
    So a healthy `ok` row and a genuine day-0 dark row are indistinguishable by
    that extract alone. Any panel or query MUST filter `status='key-missing'`
    **first**.
  - **Field-isolate before trusting a match.** `--grep` is an unanchored
    `raw LIKE '%…%'` over the single Better Stack source every host multiplexes
    into, and GitHub webhook payloads (issue and PR bodies) reach that source —
    so any issue/PR text quoting the marker name will match. A structural check
    is used rather than a `source_kind` filter because it holds regardless of
    which Vector source an echo arrives on. A trustworthy producer row has `component` =
    `claude-cost` (the pino base field from `claude-cost-marker.ts`) as a
    **top-level key** of the decoded `raw`, not as nested string content. Match
    structurally (decode `raw`, then check top-level keys) rather than by
    substring; `scripts/followthroughs/anthropic-admin-key-6297.sh` is the
    worked example, and its fixture suite mutation-proves the guard.
  - **Expect a permanently-dark surface until an account-tier decision is made.**
    The Admin API is unavailable to individual accounts, and the operator's org is
    one — `platform.claude.com/settings/admin-keys` returns "Page not found".
    Until the org is converted to a team organization, `key-missing` is the
    steady state, not a transient mint window. See ADR-108 §Consequences and
    issue #6297.

Ranked SQL (run against `remote(t520508_..._logs)`):

```sql
-- Per-cron spend/token totals over the window (per-run marker)
SELECT JSONExtractString(raw, 'source') AS source,
       count() AS runs,
       sum(JSONExtractFloat(raw, 'cost_usd')) AS cost_usd
FROM remote(t520508_..._logs)
WHERE raw LIKE '%"SOLEUR_CLAUDE_COST":true%'
GROUP BY source ORDER BY cost_usd DESC FORMAT JSONEachRow

-- Per-model spend attribution (per-run marker)
SELECT JSONExtractString(raw, 'model') AS model,
       count() AS turns,
       sum(JSONExtractFloat(raw, 'cost_usd')) AS cost_usd
FROM remote(t520508_..._logs)
WHERE raw LIKE '%"SOLEUR_CLAUDE_COST":true%'
GROUP BY model ORDER BY cost_usd DESC FORMAT JSONEachRow

-- Daily authoritative org total (Admin report)
SELECT dt, JSONExtractString(raw, 'date') AS day,
       JSONExtractFloat(raw, 'cost_usd') AS org_cost_usd
FROM remote(t520508_..._logs)
WHERE raw LIKE '%"SOLEUR_CLAUDE_COST_DAILY":true%'
ORDER BY dt DESC LIMIT 30 FORMAT JSONEachRow
```

The markers carry `conversationId`/`runId`, token counts, cost, model, and
`source` — no PII, and the daily marker is field-allowlisted so `api_key_id`/
`workspace_id` never reach Better Stack.

Two further blind spots surfaced by the cron-workspace ENOSPC incident
(#4684/#4689): (a) the `_metrics` table stores **empty** `AggregateFunction`
values — the actual metric numbers live as JSON in the `_logs` `raw` column, so
query `_logs`, not `_metrics`, for metric values. (b) The Vector host-metrics
source reports only **HOST** filesystems (the root volume), **not** the
container's `/tmp` tmpfs. That is why the 256 MB-tmpfs clone ENOSPC was invisible
here while the host root showed ~56 GB free — host metrics are structurally blind
to the per-container tmpfs the crons clone into. Disk-pressure on a cron
workspace surfaces via Sentry (`op=cron-workspace-low-disk` WARN, and the
`scheduled-output-missing` `extra.stderrTail`/`extra.exitCode`), not here.

Region scope of the query connection (#5105 session): the minted ClickHouse
connection only reaches the cluster of the data region it was provisioned
around (ours: eu-fsn-3). `remote(t<TEAM>_<table>_logs)` for a source in a
DIFFERENT region (e.g. the eu-nbg-2 onboarding demo source) fails with
`CLUSTER_DOESNT_EXIST` — use the Telemetry API (`GET /api/v1/sources`) for
metadata on out-of-region sources, or mint a second connection. Also note:
metric events shipped through the generic HTTP sink count against the LOGS
ingestion quota (3 GB/mo free tier), so quota math must include host metrics
(see knowledge-base/project/learnings/2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md).

Nested-tag extraction (#5110 second-pass session): metric rows store tags as a
nested JSON object — `JSONExtractString(raw, 'tags.mountpoint')` (dotted
single-arg path) silently returns empty strings. Use the multi-key form
`JSONExtractString(raw, 'tags', 'mountpoint')` to descend into the `tags`
object. When a tag extraction unexpectedly groups everything under one empty
key, sample one raw row (`SELECT raw ... LIMIT 1`) before trusting the path.

## Verifying disk-fullness / write-health on a deny-all host WITHOUT SSH (registry, #6122 session)

> **⚠️ Correction (#6240/#6244, 2026-07-08): triangulation does NOT prove a disk is
> *not* full.** Source 1 (Hetzner Volume API) reports the **block-device** size — NOT
> the guest **filesystem** size; these diverge if `resize2fs` failed. Source 3 ("the
> last push succeeded") does **not** prove `<85%` — zot dedups blobs and a partial
> write can still fit, so a push can succeed on a nearly-full fs. In the follow-up
> incident the disk **was** full: the volume was grown to 30 GB but `resize2fs` had
> silently failed (`|| true`), leaving the ext4 fs at ~10 GB. **For a "disk full?"
> question you MUST see the guest `df%`** — ship it as telemetry
> (`betterstack-query.sh --grep SOLEUR_ZOT_DISK` → `pcent`, `fs_size_gb`,
> `block_size_gb`), never infer fullness from the provider API. The triangulation
> below is still valid for *host-down vs cron-not-installed vs full*, but corroborate
> genuine fullness with the shipped `df%` marker. Full write-up:
> [../../../project/learnings/best-practices/2026-07-08-disk-full-reads-as-not-full-when-you-check-block-device-not-filesystem.md](../../../project/learnings/best-practices/2026-07-08-disk-full-reads-as-not-full-when-you-check-block-device-not-filesystem.md).

A disk-gated **missed-heartbeat** (e.g. `soleur-registry-disk-prd`, which pings only
while `/var/lib/zot < 85%`) is **ambiguous** on a deny-all-public host with no SSH: it
means *either* the cron isn't installed yet (benign false positive — common right after a
host `-replace`) *or* the disk genuinely crossed 85%. You cannot `df` the box. Triangulate
from three SSH-free sources instead of eyeballing a dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`):

1. **Hetzner Volume API** — `GET /v1/volumes?name=soleur-registry-store` → block-device size
   (30 GB) + attach status (the "percent full" denominator).
2. **Hetzner server disk metrics** — `GET /v1/servers/{id}/metrics?type=disk` → write activity;
   near-idle = not actively filling.
3. **The last CI release run's zot-mirror step logs** — many `pushed blob: sha256:...` with
   NO `500 no space left on device` = the disk **accepted writes** = not full. The
   success/failure of the **last real write attempt** is the most decisive SSH-free signal.

A never-pinged disk-gated heartbeat (`last_event_at` absent → cron not installed) is **NOT**
proof of disk-full — corroborate with an independent write-success signal (source 3) before
concluding either way. Read liveness from `attributes.status ∈ {paused,pending,up,down}`
(only `up` proves a ping arrived); the heartbeat API has **no `last_event_at` field**. Full
write-up: [2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md](../../../project/learnings/2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md).

## Verifying disk-fullness / write-health on a deny-all host WITHOUT SSH

A **disk-gated missed-heartbeat** (e.g. `soleur-registry-disk-prd` — pings only
while `/var/lib/zot < 85%`) is **ambiguous**: cron-not-installed false positive
vs genuine disk-full. On a deny-all-public host with no SSH you cannot `df`.
Do NOT conclude from the heartbeat alone — triangulate three SSH-free sources:

1. **Hetzner Volume API** — `GET /v1/volumes?name=<store>` → block-device size +
   attach status (the "percent full" denominator; rules out a detached volume).
2. **Hetzner server disk metrics** — `GET /v1/servers/{id}/metrics?type=disk` →
   write activity; near-idle = not actively filling.
3. **The last CI release run's zot-mirror step logs** — many `pushed blob:
   sha256:...` with **no** `500 no space left on device` = the disk **accepted
   writes** = not full. The last real write attempt's outcome is the most
   decisive SSH-free signal.

A never-pinged heartbeat (`last_event_at` absent → cron simply not installed) is
**NOT proof of disk-full** — corroborate with the independent write-success
signal (3) before concluding either way. Serves
`hr-no-dashboard-eyeball-pull-data-yourself`.

**Heartbeat liveness = `attributes.status`, not a ping timestamp.** The Better
Stack heartbeat API exposes `attributes.status ∈ {paused,pending,up,down}` and
has **no `last_event_at` field**; only `status == "up"` proves a ping arrived.
Full write-up:
[2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md](../../../project/learnings/2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md).
