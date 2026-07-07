# Phase 0 empirical spike — Inngest v1.19.4 dedicated-host extraction (#6178)

Raw evidence for the ADR. Every claim below traces to a command run against a local Docker harness of
the EXACT prod pin. Harness date: 2026-07-07.

## Harness topology (prod-fidelity)

- Server: `inngest/inngest:v1.19.4` (`1.19.4-2c8385ba8`), `ENTRYPOINT=null CMD=["inngest"]` → invoked as
  `inngest start ...`.
- **External Redis + external Postgres (matches prod: Redis queue, Postgres schedule/config/history).**
- SDK: `inngest@3.54.2` (symlinked from `apps/web-platform/node_modules/inngest`).
- Two SDK app instances, **same app id `spike-app`**, ports 13000 (inst A) / 13001 (inst B), served via
  `inngest/node` `serve()`. Functions: `cron-tick {cron:"* * * * *"}`, `hello-event {event:"test/hello"}`,
  `sleeper {event:"test/sleep"}` with `step.sleep("90s")`.
- Containers: `spike-server` (:18288→8288), `spike-redis` (:16379→6379), `spike-pg-a` (:15432),
  `spike-pg-b` (:15433), network `inngest-spike-net`. Server reaches host apps via LAN IP 192.168.86.247.
- signing-key = 64 hex (`abab…`), event-key = 32 hex (`cdcd…`). `/v0/gql` needs no auth (confirmed).

## Server flags — `inngest start --help` (v1.19.4), verbatim Persistence group

```
--postgres-uri string   PostgreSQL database URI for configuration and history persistence. Defaults to SQLite database.
--redis-uri string      Redis server URI for external queue and run state. Defaults to self-contained, in-memory Redis server with periodic snapshot backups.
--sqlite-dir string     Directory for where to write SQLite database.
--sdk-url string, -u string [ --sdk-url string, -u ... ]   App serve URLs to sync (repeatable)
--signing-key string    Must be hex string with even number of chars
--event-key string [ repeatable ]
--poll-interval int     Interval in seconds between polling for updates to apps (default 0)
```
Plus `--postgres-{max-open,max-idle,conn-max-idle-time,conn-max-lifetime}-conns` tuning.

**KEY: v1.19.4 `start` DOES expose external `--redis-uri` AND `--postgres-uri`.** The SQLite-only fallback
assumption in the plan is wrong — the exact prod topology (external Redis + Postgres) is testable locally,
so Question C was tested directly, not reasoned.

Server boot log confirms both stores active:
```
"initialized database" db=postgres
"ran database migrations" db=postgres
"using external redis" url=" redis://spike-redis:6379"
"starting event stream" backend=redis
```

---

## Question A — fan-out routing (multi `--sdk-url`, same app id): ROUTE-ONCE

### SDK identity derivation (source evidence)
`apps/web-platform/node_modules/inngest/components/InngestCommHandler.js`:
- L182 `this.id = options.id || this.client.id;`
- L1271-1286 `registerBody()` sends `appName: this.id` and `url: url.href` — the app is keyed by **appName**
  (the `new Inngest({id})` value); the serve URL is a *property* of that app, not part of its identity.
- L1300 in-band sync body: `app_id: this.id`.

Conclusion: the same `id` served at two URLs is **ONE app with one canonical URL**, not two apps.

### Server-side observation
Server started with BOTH `--sdk-url .../13000` and `.../13001` (same app id). `functions` query returns
ONE app (`app.id=247c20f5-… name=spike-app`) with each function's `url` = **the last-synced sdk-url only**
(13001 / inst B). Last-writer-wins on a single URL — no dual registration.

### Empirical trigger test (`test/hello`)
| send | event id | inst A execs | inst B execs |
|------|----------|-------------|-------------|
| clean `uniq-1783433214` | 01KWYEEE8K… | 0 | 1 |
| `rep-1` | 01KWYEFSAZ… | 0 | 1 |
| `rep-2` | 01KWYEFW9E… | 0 | 1 |
| `rep-3` | 01KWYEFZ7Z… | 0 | 1 |

Every event: exactly ONE instance (B, the current URL) ran the body; **A never executed**. `eventsV2`/`runs`
show one run per event. → **route-once**. Invoke-all (both A and B) was never observed.

Caveat (honest): in the very first trigger (during the initial sync-flap window) a second `test/hello`
event with identical payload appeared 5.5s later (`01KWYECJ40…`) → a duplicate SOURCE event, still
route-once (one run each, both on B). NOT reproduced across the 4 subsequent clean sends. Likely a
transient artifact of the two sdk-urls flapping the canonical URL during startup re-sync (poll-interval=5).

### Recommendation
Multi-`--sdk-url` is **route-once → safe from duplicate execution**. But because the winning URL is
last-writer-wins and *flaps* as the server re-polls each sdk-url, which single instance serves a given run
is non-deterministic, and a flap window can transiently perturb ingest. For a production HA pair, prefer a
**single stable `--sdk-url` pointing at a VIP/LB** in front of the app replicas (deterministic, no flap),
rather than listing replica URLs directly. Multi-sdk-url is acceptable as a fallback but not the primary.

---

## Question B — cron-run enumeration: YES, definitive GraphQL path

`Query` introspection (full field list captured) exposes a top-level **`runs(first, after, orderBy, filter,
preview)`** connection — the run-enumeration surface that needs NO prior run ids.

`RunsFilterV2` input fields (introspected):
`from: Time!`, `until: Time`, `timeField: RunsV2OrderByField` (`QUEUED_AT|STARTED_AT|ENDED_AT`),
`status: [FunctionRunStatus!]`, `functionIDs: [UUID!]`, `appIDs: [UUID!]`, `query: String`.

`FunctionRunV2` node fields (introspected):
`id, appID, app, functionID, function, traceID, queuedAt, startedAt, endedAt, status, sourceID,
triggerIDs, eventName, isBatch, batchCreatedAt, cronSchedule, output, trace, hasAI`.

### Working cron-run enumeration query (RAN, returned real data)
```graphql
query Enum($filter: RunsFilterV2!, $order: [RunsV2OrderBy!]!) {
  runs(first: 100, filter: $filter, orderBy: $order) {
    totalCount
    pageInfo { hasNextPage endCursor }
    edges { node { id functionID status queuedAt startedAt endedAt } }
  }
}
```
Variables: `{ filter: { from:"<lower>", until:"<upper>", timeField: STARTED_AT,
functionIDs:["<cron fn UUID>"] }, order:[{field: STARTED_AT, direction: ASC}] }`.

Actual result (every-minute cron, discovered UUID `920bc650-…` via `functions{id slug}`):
```
totalCount 3
  01KWYECS9K… COMPLETED startedAt 2026-07-07T14:05:59.988Z
  01KWYEEKWH… COMPLETED startedAt 2026-07-07T14:06:59.986Z
  01KWYEGEFV… COMPLETED startedAt 2026-07-07T14:07:59.996Z
```
One run per minute-bucket, distinct `startedAt`, all COMPLETED → exactly-once, zero double-fire.

- **`startedAt` (and `queuedAt`) present and reliable** on every enumerated run → usable for the
  invariant grouping `(functionID, floor(startedAt / cron_period))`; exactly-once ⇔ every occupied bucket
  has exactly 1 run.
- `cronSchedule`/`eventName` returned `null` on these run nodes (do NOT rely on them for grouping) — the
  `(functionID, startedAt-bucket)` key is the correct approach, as the plan anticipated. `scheduled_tick`
  does not exist (confirmed — not in the field set).
- Alternate path (also works): `eventsV2(filter:{includeInternalEvents:true})` surfaces each tick as an
  internal event **`inngest/scheduled.timer`** (`occurredAt` = the tick minute, e.g. `2026-07-07T14:06:00Z`)
  with nested `runs { id status startedAt endedAt }`, plus an `inngest/function.finished` per completion.
  The top-level `runs` query is cleaner (filter by functionID directly, no internal-event parsing).

### AC13 verdict
The soak probe `inngest-double-fire-6178.sh` is **demonstrably writable against the pin: YES.** The exact
query above enumerates cron runs by function id + time window and returns `startedAt` for bucketing.

---

## Question C — Redis-swap safety: FLUSHALL MANDATORY (empirically proven)

### Redis namespaces inngest v1.19.4 uses (KEYS sample)
- `{queue}:…` — queue: `partition:sorted`, `partition:item`, `queue:item`, `queue:sorted:cron`,
  `queue:sorted:cron-health-check`, `queue:sequential`, `queue:scavenger`, `queue:seen:*`, `accounts:*`.
  **The cron SCHEDULE lives in Redis (`{queue}:queue:sorted:cron`), not only Postgres.**
- `{estate:<account-uuid>}:key:*` — run/execution state (step memoization).
- `{cs}:a:<account-uuid>:ik:cc:*` — **idempotency / dedup keys, keyed by ACCOUNT id
  `00000000-0000-4000-a000-000000000000`** (default single-tenant), which is **constant across Postgres A/B**.
  Dedup namespace is therefore Postgres-independent.
- `{connect}:gateways`.

### The swap experiment (exact prod-shaped flip)
1. Server on **PG-A** + Redis. Triggered `sleeper` → run `01KWYEP6SZMR01F0GMZSS4S41T` went **RUNNING** at
   14:11:08, mid-`step.sleep("90s")` (continuation persisted in Redis; DBSIZE grew 48→77). This run exists
   **only in PG-A history**.
2. `docker rm -f spike-server`; confirmed **PG-B empty** (0 public tables) pre-swap.
3. Restarted server on **empty PG-B** + **same Redis** (14:11:34). Boot ran migrations on B; re-synced the
   3 functions from the sdk-urls immediately.
4. **Result — stale job fired against B:**
   ```
   14:11:08 SLEEPER_STARTED  runId 01KWYEP6…   (original, PG-A)
   --- swap to empty PG-B at 14:11:34 ---
   14:12:38 SLEEPER_STARTED  runId 01KWYEP6…   (step replay against B)
   14:12:38 SLEEPER_RESUMED_AFTER_SLEEP runId 01KWYEP6…  → COMPLETED against PG-B
   ```
   The `step.sleep` continuation held in Redis drove a run that **PG-B had never heard of** to completion.
   (The repeated `SLEEPER_STARTED` with the same runId is normal Inngest step-replay — the SDK re-invokes
   from the top and the memoized sleep step returns immediately; it is one run, not a double-fire.)
5. **Cron kept firing across the swap** from the stale Redis schedule: cron runs recorded in PG-B at
   14:11:59 and 14:12:59 (both after the 14:11:34 swap).
6. **Idempotency keys survived**: 7 `{cs}:a:*:ik:*` keys still present post-swap; DBSIZE 85 (all A-era
   state retained through the flip).

### Verdict
A gated **`FLUSHALL` + `DBSIZE == 0` assertion before the prod-Postgres flip is MANDATORY.** Proven: with
Redis retained, (a) in-flight `step.sleep`/queued jobs enqueued against DB-A execute against DB-B, (b) cron
schedules in Redis keep firing against DB-B, (c) account-scoped idempotency keys from DB-A persist and would
suppress/mis-dedup DB-B runs. All three are silent correctness hazards on a dark→prod cutover. Flushing
Redis (or pointing the flip at a fresh empty Redis) immediately before the Postgres flip is the only safe
sequence; assert `DBSIZE == 0` as the gate.

---

## Cleanup
All spike containers (`spike-server`, `spike-redis`, `spike-pg-a`, `spike-pg-b`), the docker network, and
both node SDK app processes were stopped/removed at end of spike. Scratch harness lived under
`/tmp/.../scratchpad/inngest-spike/` (app.js, logs).
